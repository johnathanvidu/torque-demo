#!/usr/bin/env bash
# DEMO 2 — "The revoked access" (identity/permission).
#
# Deletes the kafka-access inline policy from the app instance role, then rolls
# the consumer so it re-authenticates. MSK denies the connection; the dashboard
# shows an authorization error and the counter freezes.
#
# FIX (in the demo): the agent runs the kafka-restore-access day-2 workflow
# (re-attaches the policy + rolls the consumer). A redeploy also reconciles it.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

echo "== BREAK 2: revoke Kafka IAM access (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="

ROLE="${PREFIX}-kafka-app"
echo "  -> deleting inline policy 'kafka-access' from role ${ROLE}"
aws iam delete-role-policy --role-name "$ROLE" --policy-name kafka-access \
  || echo "  (policy already absent — already broken?)"

restart_services kafka-demo-consumer

echo "Done. Watch the dashboard: $(dashboard_url)"
echo "Symptom: consumer state = Broken, error mentions not authorized / access denied."
