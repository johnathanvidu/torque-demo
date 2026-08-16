#!/usr/bin/env bash
# Stops the consumer service, as a crash / OOM / accidental stop would. The
# infrastructure stays healthy — MSK is up, the instance is up, the producer keeps
# writing — but the consumer stops reporting and the counter freezes.
#
# Operator script — run from your laptop. See .docs/DEMO.md for how it is used.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

echo "== stop the consumer workload (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="

IID="$(instance_id)"
[ "$IID" != "None" ] || { echo "Could not find ${PREFIX}-kafka-app instance." >&2; exit 1; }

echo "  -> systemctl stop kafka-demo-consumer on ${IID}"
aws ssm send-command --instance-ids "$IID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl stop kafka-demo-consumer"]' \
  --query 'Command.CommandId' --output text >/dev/null

echo "Done. Watch the dashboard: $(dashboard_url)"
echo "Symptom: within ~10s, state = Broken, reason = consumer not reporting (process down)."
