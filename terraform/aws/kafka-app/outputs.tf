output "dashboard_url" {
  description = "Open this in a browser — the live message counter."
  value       = "http://${aws_instance.app.public_ip}:8080"
}

output "instance_id" {
  description = "App instance ID (producer + consumer + dashboard)."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP of the app instance."
  value       = aws_instance.app.public_ip
}

output "app_security_group_id" {
  description = "App security group ID."
  value       = aws_security_group.app.id
}

output "role_name" {
  description = "Instance role name."
  value       = aws_iam_role.app.name
}

output "consumer_topic_param" {
  description = "SSM parameter holding the topic the consumer subscribes to."
  value       = aws_ssm_parameter.consumer_topic.name
}
