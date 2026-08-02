output "bootstrap_brokers" {
  description = "SASL/IAM bootstrap broker string (port 9098). Wire this into the app grain."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "cluster_arn" {
  description = "ARN of the MSK cluster. Used by the app grain to scope its kafka-cluster IAM permissions."
  value       = aws_msk_cluster.this.arn
}

output "cluster_name" {
  description = "MSK cluster name (equals the demo prefix)."
  value       = aws_msk_cluster.this.cluster_name
}

output "broker_security_group_id" {
  description = "Security group protecting the brokers. The firewall demo revokes its ingress rule."
  value       = aws_security_group.brokers.id
}

output "topic_name" {
  description = "Topic the producer writes to and the consumer reads from. Wired into the app grain (grain I/O demo)."
  value       = var.topic_name
}
