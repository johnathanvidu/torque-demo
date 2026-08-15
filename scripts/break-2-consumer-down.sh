#!/usr/bin/env bash
# DEMO 2 — "The consumer workload goes down".
#
# Stops the consumer service (as a crash / OOM / accidental stop would). The
# infrastructure is all still healthy in Torque — MSK is up, the instance is up,
# the producer keeps writing — but the data pipeline is dead: the consumer stops
# reporting, so the dashboard flips to "Broken: consumer not reporting (process
# down)" and the counter freezes.
#
# FIX (in the demo): the agent runs the kafka-restart-consumer day-2 workflow to
# roll the workload. The counter resumes from where it froze.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

echo "== BREAK 2: stop the consumer workload (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="

IID="$(instance_id)"
[ "$IID" != "None" ] || { echo "Could not find ${PREFIX}-kafka-app instance." >&2; exit 1; }

echo "  -> systemctl stop kafka-demo-consumer on ${IID}"
aws ssm send-command --instance-ids "$IID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl stop kafka-demo-consumer"]' \
  --query 'Command.CommandId' --output text >/dev/null

echo "Done. Watch the dashboard: $(dashboard_url)"
echo "Symptom: within ~10s, state = Broken, reason = consumer not reporting (process down)."
