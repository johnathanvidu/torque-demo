output "db_instance_identifier" {
  description = "Identifier of the RDS instance"
  value       = module.db.db_instance_identifier
}

output "db_host" {
  description = "Hostname of the RDS instance"
  value       = module.db.db_instance_address
}

output "db_port" {
  description = "Port the database listens on"
  value       = module.db.db_instance_port
}

output "db_name" {
  description = "Name of the initial database"
  value       = module.db.db_instance_name
}

output "db_username" {
  description = "Master username"
  value       = module.db.db_instance_username
  sensitive   = true
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master password"
  value       = module.db.db_instance_master_user_secret_arn
}

output "security_group_id" {
  description = "Security group attached to the database"
  value       = aws_security_group.db.id
}
