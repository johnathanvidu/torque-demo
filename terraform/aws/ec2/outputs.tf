output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.ec2_instance.id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = module.ec2_instance.public_ip
}

output "private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = module.ec2_instance.private_ip
}

output "key_pair_name" {
  description = "Name of the generated EC2 key pair"
  value       = aws_key_pair.this.key_name
}

output "private_key_pem" {
  description = "Private key (PEM) for SSH access. Save to a .pem file and chmod 600."
  value       = tls_private_key.this.private_key_pem
  sensitive   = true
}
