#!/usr/bin/env bash
# Stops the consumer service, as a crash / OOM / accidental stop would. The
# infrastructure stays healthy — MSK is up, the instance is up, the producer keeps
# writing — but the consumer stops reporting and the counter freezes.
#
# Operator script — run from your laptop. Set PREFIX / ENV_ID to choose which
# deployment to hit; see lib.sh. Usage on stage: torque-demo/.docs/DEMO.md.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

target "stop the consumer workload"

# Already resolved (and proven running) by lib.sh.
IID="$(instance_id)"

# The systemd unit names are fixed on the instance — they do not carry the prefix.
echo "  -> systemctl stop kafka-demo-consumer on ${IID}"
aws ssm send-command --instance-ids "$IID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl stop kafka-demo-consumer"]' \
  --query 'Command.CommandId' --output text >/dev/null

echo "Done. Watch the dashboard: $(dashboard_url)"
echo "Symptom: within ~10s, state = Broken, reason = consumer not reporting (process down)."
