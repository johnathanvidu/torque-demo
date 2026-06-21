variable "name" {
  description = "Name prefix for the VPC and its resources"
  type        = string
  default     = "torque-vpc"
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_index" {
  description = "Which /24 block to carve out of the VPC CIDR (0-based)"
  type        = number
  default     = 0
}
