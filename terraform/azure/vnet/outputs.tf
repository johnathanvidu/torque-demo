output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "subnet_id" {
  description = "ID of the subnet (pass this to compute grains)."
  value       = azurerm_subnet.this.id
}

output "subnet_name" {
  description = "Name of the subnet."
  value       = azurerm_subnet.this.name
}
