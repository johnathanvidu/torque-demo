#!/usr/bin/env bash
# Shared helpers for the Kafka demo break/reset scripts.
#
# WHICH DEPLOYMENT AM I TOUCHING?
#
# Every AWS resource is named <base>-<torque environment id>-… (for example
# kafka-demo-a0mpne9x7jlx-kafka-app), so any number of these environments can run
# side by side. That makes "which one" a real question, and getting it wrong on
# stage means breaking somebody else's demo. Three ways to answer it, in order of
# precedence:
#
#   PREFIX=kafka-demo-a0mpne9x7jlx   the environment's resource_prefix output
#   ENV_ID=a0MPnE9X7jLX              the Torque environment id (case-insensitive)
#   (neither)                        discovered — allowed only when exactly one
#                                    BASE_PREFIX-* deployment is running
#
# Discovery refuses to guess between two candidates: it lists them with their
# dashboards and exits, so an ambiguous run stops instead of hitting a coin flip.
#
#   BASE_PREFIX          base name before the environment id (default kafka-demo)
#   AWS_DEFAULT_REGION   region to look in (default eu-west-1)
#
# See the torque-demo repo's .docs/DEMO.md for how these are used on stage.
set -euo pipefail

BASE_PREFIX="${BASE_PREFIX:-kafka-demo}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-eu-west-1}}"
BROKER_PORT=9098

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required but not installed." >&2; exit 1; }
}
require aws

# Resolved by resolve_deployment below, then reused by every helper — the app
# instance is the anchor for the prefix, the SSM target and the dashboard URL, so
# it is looked up once.
PREFIX="${PREFIX:-}"
APP_INSTANCE_ID=""
APP_PUBLIC_IP=""

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

resolve_deployment() {
  local pattern rows count name

  if [ -n "$PREFIX" ]; then
    pattern="${PREFIX}-kafka-app"
  elif [ -n "${ENV_ID:-}" ]; then
    # Torque shows the id mixed-case; the blueprints downcase it into resource names.
    PREFIX="${BASE_PREFIX}-$(lower "$ENV_ID")"
    pattern="${PREFIX}-kafka-app"
  else
    # tag:Name filters accept * wildcards, so this matches every deployment that
    # shares the base name, whatever environment id each one carries.
    pattern="${BASE_PREFIX}-*-kafka-app"
  fi

  rows="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${pattern}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,PublicIpAddress]' \
    --output text)"
  count="$(printf '%s\n' "$rows" | grep -c . || true)"

  if [ "$count" -eq 0 ]; then
    echo "ERROR: no running app instance named ${pattern} in ${AWS_DEFAULT_REGION}." >&2
    echo "       Wrong region, environment not active yet, or a different base name —" >&2
    echo "       pass the environment's resource_prefix output as PREFIX=… to be explicit." >&2
    exit 1
  fi

  if [ "$count" -gt 1 ]; then
    echo "ERROR: ${count} Kafka demo deployments are running. Refusing to guess which one to touch:" >&2
    printf '%s\n' "$rows" | awk '{ sub(/-kafka-app$/, "", $1);
      printf "         PREFIX=%s   (instance %s, dashboard http://%s:8080)\n", $1, $2, $3 }' >&2
    echo "       Re-run with the one you mean, e.g. PREFIX=<resource_prefix> $0" >&2
    exit 1
  fi

  name="$(printf '%s\n' "$rows" | awk 'NR==1 { print $1 }')"
  PREFIX="${name%-kafka-app}"
  APP_INSTANCE_ID="$(printf '%s\n' "$rows" | awk 'NR==1 { print $2 }')"
  APP_PUBLIC_IP="$(printf '%s\n' "$rows" | awk 'NR==1 { print $3 }')"
}

resolve_deployment

instance_id() { printf '%s' "$APP_INSTANCE_ID"; }
dashboard_url() { printf 'http://%s:8080' "$APP_PUBLIC_IP"; }

# Announce what is about to be touched. With several environments alive this line
# is the last chance to notice the script is aimed at the wrong one.
target() {
  echo "== $* =="
  echo "   target: ${PREFIX} (instance ${APP_INSTANCE_ID}, ${AWS_DEFAULT_REGION})"
}

# Group name carries the environment id too, so this resolves to one SG even with
# several deployments in the account.
broker_sg_id() {
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${PREFIX}-msk-brokers" \
    --query 'SecurityGroups[0].GroupId' --output text
}

# The mutable wiring value the consumer reads (Terraform owns it, so a redeploy
# restores it).
topic_param() { printf '/%s/consumer-topic' "$PREFIX"; }

cluster_arn() {
  aws kafka list-clusters-v2 --cluster-name-filter "${PREFIX}" \
    --query 'ClusterInfoList[0].ClusterArn' --output text
}

# Restart one or more systemd services on the app instance via SSM.
# Usage: restart_services "kafka-demo-consumer" ["kafka-demo-producer" ...]
#
# The unit names are fixed on the instance — kafka-demo-consumer/producer/dashboard
# regardless of the environment's prefix — so pass them literally.
restart_services() {
  local svc_list="$*"
  echo "  -> restarting [$svc_list] on $(instance_id) via SSM"
  aws ssm send-command --instance-ids "$(instance_id)" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"systemctl restart $svc_list\"]" \
    --query 'Command.CommandId' --output text >/dev/null
}
