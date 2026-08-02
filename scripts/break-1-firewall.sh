#!/usr/bin/env bash
# DEMO 1 — "The disappearing firewall rule" (drift).
#
# Revokes the broker security group's ingress rule, so the consumer can no longer
# reach Kafka. The dashboard state flips to "Broken" with a connection-timeout
# error and the counter freezes.
#
# FIX (in the demo): the agent redeploys the environment; Torque reconciles the
# drift and recreates the rule. (Or run scripts/reset-demo.sh / the reset workflow.)
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

echo "== BREAK 1: revoke broker firewall rule (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="

SG_ID="$(broker_sg_id)"
[ "$SG_ID" != "None" ] || { echo "Could not find ${PREFIX}-msk-brokers security group." >&2; exit 1; }

CIDR="$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`${BROKER_PORT}\`].IpRanges[0].CidrIp | [0]" \
  --output text)"

if [ "$CIDR" = "None" ] || [ -z "$CIDR" ]; then
  echo "No ingress rule on port ${BROKER_PORT} found — already broken?"
else
  echo "  -> revoking tcp/${BROKER_PORT} from ${CIDR} on ${SG_ID}"
  aws ec2 revoke-security-group-ingress --group-id "$SG_ID" \
    --protocol tcp --port "$BROKER_PORT" --cidr "$CIDR"
fi

# Force the effect to be immediate rather than waiting for connection-tracking to age out.
restart_services kafka-demo-consumer

echo "Done. Watch the dashboard: $(dashboard_url)"
echo "Symptom: consumer state = Broken, error mentions connection timeout to the brokers."
