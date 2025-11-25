output "rg_name" {
  value = azurerm_resource_group.rg.name
}

output "kv_name" {
  value = azurerm_key_vault.kv.name
}

output "location" {
  value = azurerm_resource_group.rg.location
}
