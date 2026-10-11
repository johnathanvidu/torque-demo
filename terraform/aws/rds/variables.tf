variable "name" {
  description = "Identifier for the RDS instance and prefix for its subnet group and security group. Must be unique per account/region — the blueprint should append the Torque environment id."
  type        = string
  default     = "torque-rds"
}

variable "vpc_id" {
  description = "VPC in which to create the database security group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group. Must span at least two availability zones."
  type        = list(string)
}

variable "engine" {
  description = "Database engine: postgres or mysql."
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine must be one of: postgres, mysql."
  }
}

variable "engine_version" {
  description = "Engine version. Leave null to use the default for the chosen engine (postgres 16, mysql 8.0)."
  type        = string
  default     = null
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the initial database to create."
  type        = string
  default     = "appdb"
}

variable "username" {
  description = "Master username. The password is generated and stored in AWS Secrets Manager."
  type        = string
  default     = "dbadmin"
}

variable "multi_az" {
  description = "Deploy a standby instance in a second availability zone."
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the database port. Leave empty to allow the whole VPC CIDR."
  type        = list(string)
  default     = []
}
