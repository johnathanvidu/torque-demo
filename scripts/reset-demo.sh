#!/usr/bin/env bash
# Reset the pipeline to a clean, healthy state.
#
# Operator script — run from your laptop. CLI equivalent of the kafka-reset-demo
# Torque workflow; use whichever is handier. Set PREFIX / ENV_ID to choose which
# deployment to reset; see lib.sh. Usage on stage: torque-demo/.docs/DEMO.md.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

target "RESET"

echo "[1/3] restore broker firewall rule"
SG_ID="$(broker_sg_id)"
VPC_ID="$(aws ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].VpcId' --output text)"
VPC_CIDR="$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port "$BROKER_PORT" --cidr "$VPC_CIDR" 2>/dev/null \
  && echo "  -> re-added tcp/${BROKER_PORT} from ${VPC_CIDR}" \
  || echo "  -> ingress rule already present"

echo "[2/3] restore consumer topic"
TOPIC_PARAM="$(topic_param)"
aws ssm put-parameter --name "$TOPIC_PARAM" --value "orders" --overwrite >/dev/null
echo "  -> ${TOPIC_PARAM} = orders"

echo "[3/3] (re)start consumer + producer"
restart_services kafka-demo-consumer kafka-demo-producer

echo "Reset complete. Dashboard: $(dashboard_url)"
