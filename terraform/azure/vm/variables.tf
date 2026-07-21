variable "vm_name" {
  description = "Name of the virtual machine and prefix for its associated resources."
  type        = string
  default     = "torque-vm"
}

variable "resource_group_name" {
  description = "Name of the existing resource group to deploy the VM into."
  type        = string
}

variable "location" {
  description = "Azure region in which to create the VM."
  type        = string
  default     = "eastus"
}

variable "subnet_id" {
  description = "ID of the subnet to attach the VM's network interface to."
  type        = string
}

variable "vm_size" {
  description = "Azure VM size (SKU)."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Admin username for the VM."
  type        = string
  default     = "azureuser"
}

variable "ssh_ingress_cidr" {
  description = "CIDR block allowed to reach the VM over SSH (port 22)."
  type        = string
  default     = "0.0.0.0/0"
}

# Ubuntu image reference. Defaults to the latest Ubuntu 24.04 LTS (Noble) Gen2 image.
variable "image_publisher" {
  description = "Publisher of the OS image."
  type        = string
  default     = "Canonical"
}

variable "image_offer" {
  description = "Offer of the OS image."
  type        = string
  default     = "ubuntu-24_04-lts"
}

variable "image_sku" {
  description = "SKU of the OS image."
  type        = string
  default     = "server"
}

variable "image_version" {
  description = "Version of the OS image (use 'latest' for the newest available)."
  type        = string
  default     = "latest"
}
