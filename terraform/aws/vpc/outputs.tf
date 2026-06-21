output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "subnet_id" {
  description = "ID of the calculated /24 subnet"
  value       = aws_subnet.this.id
}

output "subnet_cidr_block" {
  description = "CIDR block of the calculated /24 subnet"
  value       = aws_subnet.this.cidr_block
}
