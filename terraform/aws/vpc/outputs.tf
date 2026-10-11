output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "subnet_id" {
  description = "ID of the first /24 subnet"
  value       = aws_subnet.this[0].id
}

output "subnet_ids" {
  description = "IDs of all created /24 subnets"
  value       = aws_subnet.this[*].id
}

output "subnet_cidr_block" {
  description = "CIDR block of the first /24 subnet"
  value       = aws_subnet.this[0].cidr_block
}
