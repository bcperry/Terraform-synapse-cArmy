output "resource_group_name" {
  description = "Name of the resource group containing the Synapse workspace."
  value       = azurerm_resource_group.synapse.name
}

output "synapse_workspace_name" {
  description = "Name of the Synapse workspace created by this deployment."
  value       = azurerm_synapse_workspace.main.name
}

output "managed_identity_principal_id" {
  description = "Principal (object) ID of the user-assigned managed identity used by Synapse."
  value       = local.synapse_identity_principal_id
}

output "key_vault_uri" {
  description = "URI endpoint of the Key Vault holding the customer-managed key."
  value       = local.synapse_key_vault_uri
}
