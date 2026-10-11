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
  description = "Which /24 block of the VPC CIDR the first subnet uses (0-based); further subnets take the following blocks"
  type        = number
  default     = 0
}

variable "subnet_count" {
  description = "Number of public /24 subnets to create, spread across availability zones"
  type        = number
  default     = 1

  validation {
    condition     = var.subnet_count >= 1
    error_message = "subnet_count must be at least 1."
  }
}
