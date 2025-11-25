output "rg_name" {
  value = azurerm_resource_group.rg.name
}

output "kv_name" {
  value = azurerm_key_vault.kv.name
}

output "loc" {
  value = azurerm_resource_group.rg.location
}
