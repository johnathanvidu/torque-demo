#!/usr/bin/env bash
# Repoints the consumer's topic to an empty one. There is no error: the consumer
# connects fine and polls a topic nobody produces to, so the counter simply stops
# while everything continues to report healthy.
#
# Operator script — run from your laptop. See .docs/DEMO.md for how it is used.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

BAD_TOPIC="${BAD_TOPIC:-orders-v2}"

echo "== repoint the consumer topic (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="
echo "  -> setting /${PREFIX}/consumer-topic = ${BAD_TOPIC} (producer still writes to 'orders')"
aws ssm put-parameter --name "/${PREFIX}/consumer-topic" --value "$BAD_TOPIC" --overwrite >/dev/null

# No restart needed: the consumer re-checks this parameter every ~5s and quietly
# re-subscribes to the empty topic, so the counter simply freezes where it is.

echo "Done. Watch the dashboard: $(dashboard_url)"
echo "Symptom: within ~5s the badge goes to 'Stalled' with NO error — the counter just freezes."
