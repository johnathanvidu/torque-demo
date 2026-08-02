#!/usr/bin/env bash
# Shared helpers for the Kafka demo break/reset scripts.
#
# All scripts locate AWS resources by the environment prefix (the `prefix` input
# of the kafka-demo environment, default "kafka-demo"). Override with:
#   PREFIX=my-prefix AWS_DEFAULT_REGION=eu-west-1 ./scripts/break-1-firewall.sh
set -euo pipefail

PREFIX="${PREFIX:-kafka-demo}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-eu-west-1}}"
BROKER_PORT=9098

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required but not installed." >&2; exit 1; }
}
require aws

broker_sg_id() {
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${PREFIX}-msk-brokers" \
    --query 'SecurityGroups[0].GroupId' --output text
}

instance_id() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PREFIX}-kafka-app" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text
}

cluster_arn() {
  aws kafka list-clusters-v2 --cluster-name-filter "${PREFIX}" \
    --query 'ClusterInfoList[0].ClusterArn' --output text
}

# Restart one or more systemd services on the app instance via SSM.
# Usage: restart_services "kafka-demo-consumer" ["kafka-demo-producer" ...]
restart_services() {
  local iid svc_list
  iid="$(instance_id)"
  svc_list="$*"
  echo "  -> restarting [$svc_list] on $iid via SSM"
  aws ssm send-command --instance-ids "$iid" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"systemctl restart $svc_list\"]" \
    --query 'Command.CommandId' --output text >/dev/null
}

dashboard_url() {
  local ip
  ip="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PREFIX}-kafka-app" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
  echo "http://${ip}:8080"
}
