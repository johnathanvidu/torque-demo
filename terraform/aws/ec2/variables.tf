variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "torque-ec2"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which to create the security group"
  type        = string
}

variable "security_group_ids" {
  description = "Additional security group IDs to attach (the allow_ssh group is always attached)"
  type        = list(string)
  default     = []
}

variable "ssh_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the instance over SSH (port 22)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
