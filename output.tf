output "rg_name" {
  value = azurerm_resource_group.rg.name
  description = "The name of the Resource Group"
}

output "kv_name" {
  value = azurerm_key_vault.kv.name
  description = "The name of the Key Vault"
}

output "location" {
  value = azurerm_resource_group.rg.location
  description = "The location of the Resource Group"
}
