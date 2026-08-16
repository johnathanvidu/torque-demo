variable "name" {
  description = "Name prefix for the app resources. Break/reset scripts locate resources by this prefix (e.g. <name>-kafka-app instance, <name>-kafka-access role policy)."
  type        = string
  default     = "kafka-demo"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_id" {
  description = "VPC to launch the app instance in (same VPC as the MSK brokers)."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet for the app instance (needs egress to pull the app + a public IP for the dashboard)."
  type        = string
}

variable "bootstrap_brokers" {
  description = "MSK SASL/IAM bootstrap broker string. Wired from the msk grain output."
  type        = string
}

variable "cluster_arn" {
  description = "MSK cluster ARN. Used to scope the kafka-cluster IAM permissions. Wired from the msk grain output."
  type        = string
}

variable "topic_name" {
  description = "Topic the producer writes to and the consumer starts on. Wired from the msk grain output."
  type        = string
  default     = "orders"
}

variable "instance_type" {
  description = "App instance type."
  type        = string
  default     = "t3.small"
}

variable "dashboard_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the dashboard on port 8080."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
