variable "name" {
  description = "Name of the resource group to create."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the resource group."
  type        = string
  default     = "eastus"
}
