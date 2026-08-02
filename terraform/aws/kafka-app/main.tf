data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-al2023/latest/al2023-ami-kernel-default-x86_64"
}

locals {
  # Derive the topic/group ARNs from the cluster ARN so the kafka-access policy
  # is scoped to exactly this cluster.
  #   cluster: arn:aws:kafka:region:acct:cluster/NAME/UUID
  #   topic:   arn:aws:kafka:region:acct:topic/NAME/UUID/<topic>
  #   group:   arn:aws:kafka:region:acct:group/NAME/UUID/<group>
  topic_arns = "${replace(var.cluster_arn, ":cluster/", ":topic/")}/*"
  group_arns = "${replace(var.cluster_arn, ":cluster/", ":group/")}/*"

  app_files = fileset("${path.module}/app", "**")
}

# --- artifact bucket: how the app code reaches the instance ------------------
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "app" {
  bucket        = "${var.name}-app-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Name = "${var.name}-app"
  }
}

resource "aws_s3_object" "app" {
  for_each = local.app_files
  bucket   = aws_s3_bucket.app.id
  key      = "app/${each.value}"
  source   = "${path.module}/app/${each.value}"
  etag     = filemd5("${path.module}/app/${each.value}")
}

# --- the mutable wiring value the consumer reads -----------------------------
# Declared here (from the wired topic_name input) so a Torque redeploy reconciles
# it. The "grain I/O wiring" demo overwrites this out-of-band to orders-v2.
resource "aws_ssm_parameter" "consumer_topic" {
  name  = "/${var.name}/consumer-topic"
  type  = "String"
  value = var.topic_name

  tags = {
    Name = "${var.name}-consumer-topic"
  }
}

# --- app security group ------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Kafka demo app (dashboard) access"
  vpc_id      = var.vpc_id

  ingress {
    description = "Dashboard"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.dashboard_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-app"
  }
}

# --- instance role -----------------------------------------------------------
resource "aws_iam_role" "app" {
  name = "${var.name}-kafka-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.name}-kafka-app"
  }
}

# Lets the break/reset scripts and the day-2 workflows restart services via SSM.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Baseline: pull the app from S3 and read the consumer-topic parameter.
resource "aws_iam_role_policy" "runtime" {
  name = "runtime"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.app.arn, "${aws_s3_bucket.app.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.consumer_topic.arn
      },
    ]
  })
}

# THE "revoked access" demo target. Kept as its own inline policy so a break
# script can `aws iam delete-role-policy --policy-name kafka-access` and a Torque
# redeploy (or the restore-access workflow) puts it back.
resource "aws_iam_role_policy" "kafka_access" {
  name = "kafka-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:DescribeClusterDynamicConfiguration",
          "kafka-cluster:AlterCluster",
        ]
        Resource = var.cluster_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:DescribeTopicDynamicConfiguration",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
        ]
        Resource = local.topic_arns
      },
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
        Resource = local.group_arns
      },
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-kafka-app"
  role = aws_iam_role.app.name
}

# --- the app instance --------------------------------------------------------
resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    region         = var.region
    app_bucket     = aws_s3_bucket.app.id
    brokers        = var.bootstrap_brokers
    producer_topic = var.topic_name
    topic_param    = aws_ssm_parameter.consumer_topic.name
    consumer_group = "${var.name}-consumers"
    status_file    = "/var/lib/kafka-demo/status.json"
  })

  # Make sure the code is in the bucket before the instance tries to sync it.
  depends_on = [aws_s3_object.app]

  tags = {
    Name = "${var.name}-kafka-app"
  }
}
