output "resource_group_name" {
  description = "Created Resource Group name"
  value       = azurerm_resource_group.demo.name
}

output "resource_group_id" {
  description = "Created Resource Group Azure resource ID"
  value       = azurerm_resource_group.demo.id
}

output "resource_group_location" {
  description = "Resource Group region"
  value       = azurerm_resource_group.demo.location
}
