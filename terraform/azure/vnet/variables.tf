variable "name" {
  description = "Name prefix for the virtual network and its subnet."
  type        = string
  default     = "torque-vnet"
}

variable "resource_group_name" {
  description = "Name of the existing resource group to create the virtual network in."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the virtual network."
  type        = string
  default     = "eastus"
}

variable "address_space" {
  description = "Address space for the virtual network, as a list of CIDR blocks."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_prefix" {
  description = "CIDR block for the subnet (must be within the VNet address space)."
  type        = string
  default     = "10.0.1.0/24"
}
