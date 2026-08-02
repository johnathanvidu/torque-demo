#!/usr/bin/env bash
# Reset the Kafka demo to a clean, healthy state between takes.
#
# Restores all three break targets directly via the AWS CLI (firewall rule,
# kafka-access policy, consumer topic) and rolls the consumer + producer. This is
# the CLI equivalent of the kafka-reset-demo Torque workflow — use whichever is
# handier on stage.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh

echo "== RESET (prefix=${PREFIX}, region=${AWS_DEFAULT_REGION}) =="

echo "[1/4] restore broker firewall rule"
SG_ID="$(broker_sg_id)"
VPC_ID="$(aws ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].VpcId' --output text)"
VPC_CIDR="$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --protocol tcp --port "$BROKER_PORT" --cidr "$VPC_CIDR" 2>/dev/null \
  && echo "  -> re-added tcp/${BROKER_PORT} from ${VPC_CIDR}" \
  || echo "  -> ingress rule already present"

echo "[2/4] restore kafka-access policy"
ARN="$(cluster_arn)"
TOPIC_ARN="$(echo "$ARN" | sed 's#:cluster/#:topic/#')/*"
GROUP_ARN="$(echo "$ARN" | sed 's#:cluster/#:group/#')/*"
POLICY=$(printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["kafka-cluster:Connect","kafka-cluster:DescribeCluster","kafka-cluster:DescribeClusterDynamicConfiguration","kafka-cluster:AlterCluster"],"Resource":"%s"},{"Effect":"Allow","Action":["kafka-cluster:CreateTopic","kafka-cluster:DescribeTopic","kafka-cluster:DescribeTopicDynamicConfiguration","kafka-cluster:WriteData","kafka-cluster:ReadData"],"Resource":"%s"},{"Effect":"Allow","Action":["kafka-cluster:AlterGroup","kafka-cluster:DescribeGroup"],"Resource":"%s"}]}' "$ARN" "$TOPIC_ARN" "$GROUP_ARN")
aws iam put-role-policy --role-name "${PREFIX}-kafka-app" --policy-name kafka-access --policy-document "$POLICY"
echo "  -> re-attached kafka-access"

echo "[3/4] restore consumer topic"
aws ssm put-parameter --name "/${PREFIX}/consumer-topic" --value "orders" --overwrite >/dev/null
echo "  -> /${PREFIX}/consumer-topic = orders"

echo "[4/4] roll consumer + producer"
restart_services kafka-demo-consumer kafka-demo-producer

echo "Reset complete. Dashboard: $(dashboard_url)"
