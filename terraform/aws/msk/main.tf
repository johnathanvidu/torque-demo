data "aws_availability_zones" "available" {
  state = "available"
}

# One broker subnet per entry in broker_subnet_indices, spread across AZs.
# These live in the same VPC as the app instance, so intra-VPC (local) routing
# lets the app reach the brokers on their private IPs — no IGW/NAT needed here.
resource "aws_subnet" "brokers" {
  count             = length(var.broker_subnet_indices)
  vpc_id            = var.vpc_id
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 24 - tonumber(split("/", var.vpc_cidr_block)[1]), var.broker_subnet_indices[count.index])
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name}-msk-broker-${count.index}"
  }
}

# Security group for the brokers. The ingress rule that lets clients reach the
# brokers is defined as a SEPARATE resource on purpose: the "firewall" demo
# revokes exactly this rule out-of-band, and a Torque redeploy reconciles the
# drift by recreating it.
resource "aws_security_group" "brokers" {
  name        = "${var.name}-msk-brokers"
  description = "MSK broker access for the ${var.name} demo"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-msk-brokers"
  }
}

resource "aws_security_group_rule" "brokers_iam" {
  description       = "Kafka IAM (SASL_SSL) from inside the VPC"
  type              = "ingress"
  from_port         = 9098
  to_port           = 9098
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr_block]
  security_group_id = aws_security_group.brokers.id
}

resource "aws_msk_configuration" "this" {
  name           = "${var.name}-config"
  kafka_versions = [var.kafka_version]

  # auto.create.topics lets the "orders-v2" topic in the wiring demo come into
  # existence empty, so the consumer polls it silently (no error) — exactly the
  # "silent stop" we want to demo.
  server_properties = <<-PROPERTIES
    auto.create.topics.enable=true
    delete.topic.enable=true
    default.replication.factor=2
    min.insync.replicas=1
    num.partitions=1
  PROPERTIES
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = length(aws_subnet.brokers)

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = aws_subnet.brokers[*].id
    security_groups = [aws_security_group.brokers.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size
      }
    }
  }

  # IAM authentication only — clients authenticate with their instance role, so
  # the "revoked access" demo just detaches an IAM policy (no passwords to manage).
  client_authentication {
    sasl {
      iam = true
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  tags = {
    Name = var.name
  }
}
