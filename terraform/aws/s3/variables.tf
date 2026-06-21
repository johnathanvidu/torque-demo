variable "name" {
  description = "Name of S3 bucket"
  type        = string
}

variable "region" {
  description = "Region in which to create the bucket"
  type        = string
  default     = "eu-west-1"
}