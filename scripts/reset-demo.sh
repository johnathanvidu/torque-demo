#!/usr/bin/env bash
# Reset the Kafka demo to a clean, healthy state between takes.
#
# Restores the broker firewall rule and the consumer topic, and makes sure the
# consumer + producer are running. This is the CLI equivalent of the
# kafka-reset-demo Torque workflow — use whichever is handier on stage.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

echo "== RESET (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="

echo "[1/3] restore broker firewall rule"
SG_ID="$(broker_sg_id)"
VPC_ID="$(aws ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].VpcId' --output text)"
VPC_CIDR="$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port "$BROKER_PORT" --cidr "$VPC_CIDR" 2>/dev/null \
  && echo "  -> re-added tcp/${BROKER_PORT} from ${VPC_CIDR}" \
  || echo "  -> ingress rule already present"

echo "[2/3] restore consumer topic"
aws ssm put-parameter --name "/${PREFIX}/consumer-topic" --value "orders" --overwrite >/dev/null
echo "  -> /${PREFIX}/consumer-topic = orders"

echo "[3/3] (re)start consumer + producer"
restart_services kafka-demo-consumer kafka-demo-producer

echo "Reset complete. Dashboard: $(dashboard_url)"
