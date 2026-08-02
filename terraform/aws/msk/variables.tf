variable "name" {
  description = "Name prefix for the MSK cluster and its resources. Also used as the tag prefix the demo break/reset scripts search on."
  type        = string
  default     = "kafka-demo"
}

variable "vpc_id" {
  description = "VPC in which to place the MSK broker subnets and security group."
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC. Broker ingress on 9098 is allowed from this range so clients in the same VPC can reach the brokers."
  type        = string
}

variable "broker_subnet_indices" {
  description = "Which /24 blocks to carve out of the VPC CIDR for the broker subnets (one per AZ). Use high indices to avoid clashing with the app subnet."
  type        = list(number)
  default     = [10, 11]
}

variable "kafka_version" {
  description = "Apache Kafka version for the MSK cluster."
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "Broker instance type."
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_ebs_volume_size" {
  description = "EBS volume size (GiB) per broker."
  type        = number
  default     = 20
}

variable "topic_name" {
  description = "Logical topic the producer writes to and the consumer reads from. Surfaced as an output so it can be wired into the app grain."
  type        = string
  default     = "orders"
}
