#!/usr/bin/env bash
# Kafka demo health check.
#
# Unlike the break-*/reset scripts in this folder, this one runs on the TORQUE
# AGENT, not your laptop — it is the body of the `health_check` shell grain in
# blueprints/aws-kafka-complete.yaml, and the kafka-health-check day-2 workflow
# re-runs that grain to refresh the environment's health outputs.
#
# It answers one question — "is the Kafka pipeline actually working?" — by
# probing exactly the three things the demo breaks, in root-cause order:
#
#   1. broker firewall   MSK broker SG still allows tcp/9098 from the VPC CIDR
#   2. consumer process  kafka-demo-consumer is running and writing a fresh heartbeat
#   3. topic wiring      /$PREFIX/consumer-topic still matches the producer's topic
#
# Order matters: a firewall break leaves the consumer running (so check 2 would
# pass) and on the right topic (so check 3 would pass) — it just can't connect.
# Reporting the first failing check in this order reports the root cause.
#
# SOURCED, not executed (`source health-check.sh`), so the exported outputs are
# visible to the grain. That rules out `set -e`: a non-zero probe would kill the
# grain's shell before anything is exported. Every probe is individually guarded
# instead, and an unreachable probe degrades to UNKNOWN rather than a crash.
#
# In:  PREFIX, AWS_DEFAULT_REGION, EXPECTED_TOPIC, VPC_CIDR, INSTANCE_ID,
#      FAIL_ON_UNHEALTHY
# Out: kafka_health, failing_check, health_summary, messages_processed
set -u

BROKER_PORT=9098
# The consumer rewrites status.json every ~2s; the dashboard calls it stale at 8s.
# We are more tolerant because we are reading it through SSM round-trips.
STALE_AFTER_S=15
# The producer writes every 3s. Connected + on-topic + no message for this long
# is the silent wiring break.
STALL_AFTER_S=30
# Cold start. The app grain returns as soon as EC2 reports "running", but
# user-data still has to install deps, unpack the app and write the systemd
# units — a minute or two in which the consumer legitimately does not exist yet.
# Overridable, because instance boot times vary.
BOOT_GRACE_S="${BOOT_GRACE_S:-300}"
BOOT_POLL_S="${BOOT_POLL_S:-15}"

log() { echo "[health] $*"; }

# Seconds between $1 (epoch now) and $2 (epoch float, possibly empty).
# Prints -1 when $2 is empty, which every caller treats as "unknown, skip".
age_since() {
  awk -v now="$1" -v then="$2" 'BEGIN { if (then == "") print -1; else printf "%d", now - then }'
}

health="HEALTHY"
failing="none"
summary="Producer -> Kafka -> consumer flowing normally."
count="unknown"

# --- 1. broker firewall ------------------------------------------------------
sg_id="$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${PREFIX}-msk-brokers" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)"

fw_ok="unknown"
if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
  # Single-quoted around the backticks so bash does not treat them as command
  # substitution before JMESPath ever sees them.
  cidrs="$(aws ec2 describe-security-groups --group-ids "$sg_id" \
    --query 'SecurityGroups[0].IpPermissions[?ToPort==`'"$BROKER_PORT"'`].IpRanges[].CidrIp' \
    --output text 2>/dev/null)"
  case " $cidrs " in
    *" $VPC_CIDR "*) fw_ok="yes" ;;
    *)               fw_ok="no" ;;
  esac
fi
log "1/3 broker firewall: sg=${sg_id:-?}, allows ${VPC_CIDR} on ${BROKER_PORT}? ${fw_ok}"

# --- 2. consumer process + heartbeat ----------------------------------------
# One SSM command returns both signals: line 1 is systemd's view of the service,
# the rest is the status file the consumer heartbeats into.
svc="unknown"
state="unknown"
last_error=""
hb_age=-1
msg_age=-1

probe_consumer() {
  local cmd_id inv out json now
  svc="unknown"; state="unknown"; count="unknown"; last_error=""; hb_age=-1; msg_age=-1

  cmd_id="$(aws ssm send-command --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters 'commands=["systemctl is-active kafka-demo-consumer || true","cat /var/lib/kafka-demo/status.json 2>/dev/null || echo {}"]' \
    --query 'Command.CommandId' --output text 2>/dev/null)"
  [ -n "$cmd_id" ] && [ "$cmd_id" != "None" ] || return 0

  for _ in $(seq 1 20); do
    sleep 2
    inv="$(aws ssm get-command-invocation --command-id "$cmd_id" \
      --instance-id "$INSTANCE_ID" --query 'Status' --output text 2>/dev/null || echo Pending)"
    case "$inv" in Success | Failed | Cancelled | TimedOut) break ;; esac
  done

  out="$(aws ssm get-command-invocation --command-id "$cmd_id" \
    --instance-id "$INSTANCE_ID" --query 'StandardOutputContent' --output text 2>/dev/null)"

  svc="$(printf '%s\n' "$out" | head -1 | tr -d '[:space:]')"
  json="$(printf '%s\n' "$out" | tail -n +2)"

  now="$(date +%s)"
  state="$(printf '%s' "$json" | jq -r '.state // "unknown"' 2>/dev/null || echo unknown)"
  count="$(printf '%s' "$json" | jq -r '.count // "unknown"' 2>/dev/null || echo unknown)"
  last_error="$(printf '%s' "$json" | jq -r '.last_error // empty' 2>/dev/null)"
  hb_age="$(age_since "$now" "$(printf '%s' "$json" | jq -r '.updated_at // empty' 2>/dev/null)")"
  msg_age="$(age_since "$now" "$(printf '%s' "$json" | jq -r '.last_message_ts // empty' 2>/dev/null)")"
}

probe_consumer

# Readiness gate. A consumer that has never carried a message might simply not
# have booted yet, so wait for it rather than judging it — this is what makes the
# grain safe to run at the end of the initial deployment.
#
# The wait is entered ONLY when no message has ever arrived. Demo 2 stops a
# consumer that has already been running, so its status file survives with a real
# last_message_ts and reports instantly, with no grace period. Same for Demo 3.
# `fw_ok != unknown` proves the agent's AWS credentials work, so we are waiting on
# the app, not on a permissions problem.
if [ "$fw_ok" != "unknown" ] && [ "$msg_age" -lt 0 ] && [ "$state" != "error" ]; then
  log "2/3 consumer process: no message processed yet — waiting up to ${BOOT_GRACE_S}s for the app to finish booting"
  deadline=$(($(date +%s) + BOOT_GRACE_S))
  while [ "$msg_age" -lt 0 ] && [ "$state" != "error" ] && [ "$(date +%s)" -lt "$deadline" ]; do
    sleep "$BOOT_POLL_S"
    probe_consumer
    log "    systemd=${svc}, state=${state}, count=${count}, last message ${msg_age}s ago"
  done
fi
log "2/3 consumer process: systemd=${svc}, state=${state}, count=${count}, heartbeat ${hb_age}s ago, last message ${msg_age}s ago"

# --- 3. topic wiring ---------------------------------------------------------
actual_topic="$(aws ssm get-parameter --name "/${PREFIX}/consumer-topic" \
  --query 'Parameter.Value' --output text 2>/dev/null)"
log "3/3 topic wiring: consumer reads '${actual_topic:-?}', producer writes '${EXPECTED_TOPIC}'"

# --- verdict -----------------------------------------------------------------
if [ "$fw_ok" = "unknown" ] && [ "$svc" = "unknown" ]; then
  health="UNKNOWN"
  failing="probe_failed"
  summary="Could not probe the environment — check the agent's AWS permissions (ec2:DescribeSecurityGroups, ssm:SendCommand, ssm:GetCommandInvocation, ssm:GetParameter) and that it is in ${AWS_DEFAULT_REGION}."

elif [ "$fw_ok" = "no" ]; then
  health="BROKEN"
  failing="broker_firewall"
  summary="Broker security group ${sg_id} is missing tcp/${BROKER_PORT} ingress from ${VPC_CIDR}, so the consumer cannot reach MSK. The blueprint declares this rule — reconcile/redeploy the environment to put it back."

elif [ "$hb_age" -lt 0 ]; then
  # Never wrote a status file at all, even after the grace period — so it never
  # came up, rather than having come up and died. Not one of the three demo
  # breaks: the app failed to bootstrap.
  health="BROKEN"
  failing="consumer_never_started"
  summary="The consumer never reported in ${BOOT_GRACE_S}s (systemd: ${svc}). This is a bootstrap failure, not a demo break — check /var/log/cloud-init-output.log on ${INSTANCE_ID}."

elif [ "$svc" != "active" ] || [ "$hb_age" -gt "$STALE_AFTER_S" ]; then
  health="BROKEN"
  failing="consumer_process"
  summary="The consumer workload is down (systemd reports '${svc}', last heartbeat ${hb_age}s ago). Infrastructure is fine; only the pipeline is dead. Run the kafka-restart-consumer workflow."

elif [ -n "$actual_topic" ] && [ "$actual_topic" != "None" ] && [ "$actual_topic" != "$EXPECTED_TOPIC" ]; then
  health="STALLED"
  failing="topic_wiring"
  summary="Wiring drift: the consumer reads '${actual_topic}' but the producer writes '${EXPECTED_TOPIC}', so the counter is frozen at ${count} with no error. Run the kafka-restore-topic workflow."

elif [ "$state" = "error" ]; then
  health="BROKEN"
  failing="consumer_error"
  summary="The consumer is running but erroring against Kafka: ${last_error}"

elif [ "$msg_age" -lt 0 ]; then
  # Heartbeating, on the right topic, no error — but nothing ever arrived.
  health="STALLED"
  failing="no_messages"
  summary="The consumer is up and on the right topic but processed nothing in ${BOOT_GRACE_S}s — check kafka-demo-producer on ${INSTANCE_ID}."

elif [ "$msg_age" -gt "$STALL_AFTER_S" ]; then
  health="STALLED"
  failing="no_messages"
  summary="Consumer is connected and on the right topic, but nothing has arrived for ${msg_age}s — check the producer."
fi

log "=> ${health} (${failing}): ${summary}"

export kafka_health="$health"
export failing_check="$failing"
export health_summary="$summary"
export messages_processed="$count"

# Opt-in: surface an unhealthy pipeline as a red grain (environment goes "Active
# with Error") instead of a green grain carrying a BROKEN output. Off by default
# because a failed grain does not publish its outputs — you get the alarm but
# lose the diagnosis. Turn it on only if you want the environment itself to go red.
if [ "${FAIL_ON_UNHEALTHY:-false}" = "true" ] && [ "$health" != "HEALTHY" ]; then
  log "FAIL_ON_UNHEALTHY=true and health=${health} — failing the grain."
  return 1 2>/dev/null || exit 1
fi
