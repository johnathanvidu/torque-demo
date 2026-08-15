#!/usr/bin/env bash
# DEMO 3 — "The mismatched wiring" (grain I/O drift, silent failure).
#
# Repoints the consumer's topic (the value wired from the MSK grain) to an empty
# topic 'orders-v2'. There is NO error: the consumer connects fine and polls a
# topic nobody produces to. The counter simply stops. This is the one a human
# stares at for an hour — both grains report healthy.
#
# FIX (in the demo): the agent inspects the grain I/O, spots that the consumer's
# topic no longer matches the producer/MSK-wired 'orders', and runs the
# kafka-restore-topic workflow (or redeploy).
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

BAD_TOPIC="${BAD_TOPIC:-orders-v2}"

echo "== BREAK 3: drift the consumer topic (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="
echo "  -> setting /${PREFIX}/consumer-topic = ${BAD_TOPIC} (producer still writes to 'orders')"
aws ssm put-parameter --name "/${PREFIX}/consumer-topic" --value "$BAD_TOPIC" --overwrite >/dev/null

# No restart needed: the consumer re-checks this parameter every ~5s and quietly
# re-subscribes to the empty topic, so the counter simply freezes where it is.

echo "Done. Watch the dashboard: $(dashboard_url)"
echo "Symptom: within ~5s the badge goes to 'Stalled' with NO error — the counter just freezes."
