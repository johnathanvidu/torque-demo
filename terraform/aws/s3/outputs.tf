output "s3_bucket_id" {
  description = "Name (ID) of the S3 bucket"
  value       = aws_s3_bucket.bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.bucket.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Region-specific domain name of the S3 bucket"
  value       = aws_s3_bucket.bucket.bucket_regional_domain_name
}

output "s3_bucket_region" {
  description = "Region the bucket resides in"
  value       = aws_s3_bucket.bucket.region
}
