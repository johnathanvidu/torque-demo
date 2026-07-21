output "vm_id" {
  description = "ID of the virtual machine."
  value       = azurerm_linux_virtual_machine.this.id
}

output "vm_name" {
  description = "Name of the virtual machine."
  value       = azurerm_linux_virtual_machine.this.name
}

output "public_ip" {
  description = "Public IP address of the virtual machine."
  value       = azurerm_public_ip.this.ip_address
}

output "private_ip" {
  description = "Private IP address of the virtual machine."
  value       = azurerm_linux_virtual_machine.this.private_ip_address
}

output "admin_username" {
  description = "Admin username for SSH access."
  value       = azurerm_linux_virtual_machine.this.admin_username
}

output "ssh_private_key_pem" {
  description = "Private key (PEM) for SSH access. Save to a .pem file and chmod 600."
  value       = tls_private_key.this.private_key_pem
  sensitive   = true
}
