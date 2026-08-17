#!/usr/bin/env bash
# Kafka demo health check.
#
# Unlike the break-*/reset scripts in this folder, this one runs on the TORQUE
# AGENT, not your laptop — it is the body of the `health_check` shell grain in
# blueprints/aws-kafka-complete.yaml, and the kafka-health-check day-2 workflow
# re-runs that grain to refresh the environment's health outputs.
#
# WHAT IT REPORTS, AND WHAT IT DELIBERATELY DOES NOT
#
# It answers one question — "is the Kafka pipeline processing messages?" — and
# publishes only the outward SYMPTOM: never a root cause, never a remedy.
#
# The verdict collapses to the three conditions an observer can actually see,
# matching the dashboard's three badges:
#
#   A. the consumer is not reporting at all
#   B. the consumer is up but its connection to Kafka is failing
#   C. the consumer is connected and error-free, yet nothing is arriving
#
# Distinct underlying causes that present identically from outside intentionally
# produce identical text; separating them requires investigating the live
# environment, which is not this script's job.
#
# Internally it still probes each suspect, because that is what decides
# healthy-vs-not and drives the boot grace. That detail is logged only when
# HEALTH_DEBUG=true.
#
# SOURCED, not executed (`source health-check.sh`), so the exported outputs are
# visible to the grain. That rules out `set -e`: a non-zero probe would kill the
# grain's shell before anything is exported. Every probe is individually guarded
# instead, and an unreachable probe degrades to UNKNOWN rather than a crash.
#
# In:  PREFIX, AWS_DEFAULT_REGION, EXPECTED_TOPIC, VPC_CIDR, INSTANCE_ID,
#      FAIL_ON_UNHEALTHY, HEALTH_DEBUG
# Out: kafka_health, health_summary, messages_processed
set -u

BROKER_PORT=9098
# The consumer rewrites status.json every ~2s; the dashboard calls it stale at 8s.
# We are more tolerant because we are reading it through SSM round-trips.
STALE_AFTER_S=15
# The producer writes every 3s. Connected + on-topic + no message for this long
# is a silent stall.
STALL_AFTER_S=30
# Cold start. The app grain returns as soon as EC2 reports "running", but
# user-data still has to install deps, unpack the app and write the systemd
# units — a minute or two in which the consumer legitimately does not exist yet.
# Overridable, because instance boot times vary.
BOOT_GRACE_S="${BOOT_GRACE_S:-300}"
BOOT_POLL_S="${BOOT_POLL_S:-15}"
# Off by default: the per-probe detail names which individual check failed,
# which is more than the published symptom is meant to reveal.
HEALTH_DEBUG="${HEALTH_DEBUG:-false}"

log() { echo "[health] $*"; }
# `return 0` so a suppressed debug line never becomes the caller's exit status.
dbg() {
  [ "$HEALTH_DEBUG" = "true" ] && echo "[health] $*"
  return 0
}

# Seconds between $1 (epoch now) and $2 (epoch float, possibly empty).
# Prints -1 when $2 is empty, which every caller treats as "unknown, skip".
age_since() {
  awk -v now="$1" -v then="$2" 'BEGIN { if (then == "") print -1; else printf "%d", now - then }'
}

# The three outward symptoms. Phrased so that neither the cause nor the fix
# leaks — see the header.
SYM_SILENT_PROCESS="The consumer process is not reporting."
SYM_CONNECTION="The consumer is running, but its connection to Kafka is failing."
SYM_NO_TRAFFIC="The consumer reports connected and healthy, with no error."

health="HEALTHY"
failing="none"
summary="Producer -> Kafka -> consumer flowing normally."
count="unknown"

# Composes a symptom-level summary: what is observably wrong, plus the frozen
# counter, and nothing that points at a suspect.
symptom() {
  printf 'Pipeline is not processing messages. %s Messages processed: %s.' "$1" "$count"
}

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
dbg "1/3 broker firewall: sg=${sg_id:-?}, allows ${VPC_CIDR} on ${BROKER_PORT}? ${fw_ok}"

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
# The wait is entered ONLY when no message has ever arrived. A consumer that ran
# and then stopped leaves a status file behind with a real last_message_ts, so it
# is judged immediately with no grace period. `fw_ok != unknown` proves the
# agent's AWS credentials work, so we are waiting on the app, not on permissions.
if [ "$fw_ok" != "unknown" ] && [ "$msg_age" -lt 0 ] && [ "$state" != "error" ]; then
  log "No message processed yet — waiting up to ${BOOT_GRACE_S}s for the app to finish starting."
  deadline=$(($(date +%s) + BOOT_GRACE_S))
  while [ "$msg_age" -lt 0 ] && [ "$state" != "error" ] && [ "$(date +%s)" -lt "$deadline" ]; do
    sleep "$BOOT_POLL_S"
    probe_consumer
    dbg "    systemd=${svc}, state=${state}, count=${count}, last message ${msg_age}s ago"
  done
fi
dbg "2/3 consumer process: systemd=${svc}, state=${state}, count=${count}, heartbeat ${hb_age}s ago, last message ${msg_age}s ago"

# --- 3. topic wiring ---------------------------------------------------------
actual_topic="$(aws ssm get-parameter --name "/${PREFIX}/consumer-topic" \
  --query 'Parameter.Value' --output text 2>/dev/null)"
dbg "3/3 topic wiring: consumer reads '${actual_topic:-?}', producer writes '${EXPECTED_TOPIC}'"

# --- verdict -----------------------------------------------------------------
# Branch order is still root-cause order, because that is what makes the
# classification correct. Only the *wording* is symptom-level.
if [ "$fw_ok" = "unknown" ] && [ "$svc" = "unknown" ]; then
  # Not a pipeline verdict at all — the probe itself could not run, so this one
  # stays explicit. It says nothing about the demo breaks.
  health="UNKNOWN"
  failing="probe_failed"
  summary="Could not probe the environment — check the agent's AWS permissions (ec2:DescribeSecurityGroups, ssm:SendCommand, ssm:GetCommandInvocation, ssm:GetParameter) and that it is in ${AWS_DEFAULT_REGION}."

elif [ "$fw_ok" = "no" ]; then
  health="BROKEN"
  failing="broker_firewall"
  summary="$(symptom "$SYM_CONNECTION")"

elif [ "$hb_age" -lt 0 ]; then
  # Never wrote a status file at all, even after the grace period.
  health="BROKEN"
  failing="consumer_never_started"
  summary="Pipeline is not processing messages. The consumer has not reported since the environment deployed."

elif [ "$svc" != "active" ] || [ "$hb_age" -gt "$STALE_AFTER_S" ]; then
  health="BROKEN"
  failing="consumer_process"
  summary="$(symptom "$SYM_SILENT_PROCESS")"

elif [ -n "$actual_topic" ] && [ "$actual_topic" != "None" ] && [ "$actual_topic" != "$EXPECTED_TOPIC" ]; then
  health="STALLED"
  failing="topic_wiring"
  summary="$(symptom "$SYM_NO_TRAFFIC")"

elif [ "$state" = "error" ]; then
  health="BROKEN"
  failing="consumer_error"
  summary="$(symptom "$SYM_CONNECTION")"

elif [ "$msg_age" -lt 0 ]; then
  health="STALLED"
  failing="no_messages"
  summary="$(symptom "$SYM_NO_TRAFFIC")"

elif [ "$msg_age" -gt "$STALL_AFTER_S" ]; then
  health="STALLED"
  failing="no_messages"
  summary="$(symptom "$SYM_NO_TRAFFIC")"
fi

log "=> ${health}: ${summary}"
dbg "   internal classification: ${failing}"

export kafka_health="$health"
export health_summary="$summary"
export messages_processed="$count"

# Surface an unhealthy pipeline as a red grain, so the environment goes "Active
# with Error" instead of sitting green while carrying a BROKEN output.
#
# Note the outputs above are exported BEFORE this point deliberately: whether
# Torque still harvests a failed command's outputs is not documented, so ordering
# it this way gives them the best chance of being published either way.
if [ "${FAIL_ON_UNHEALTHY:-false}" = "true" ] && [ "$health" != "HEALTHY" ]; then
  log "FAIL_ON_UNHEALTHY=true and health=${health} — failing the grain."
  return 1 2>/dev/null || exit 1
fi
