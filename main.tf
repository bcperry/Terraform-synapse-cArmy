data "azurerm_client_config" "current" {}

locals {
  # Ensure generated names satisfy Azure constraints.
  resource_group_name      = lower(format("%s-rg-%s", var.prefix, var.environment))
  primary_storage_name     = substr(lower(replace("${var.prefix}${var.environment}dlgsyn", "-", "")), 0, 24)
  diagnostics_storage_name = substr(lower(replace("${var.prefix}${var.environment}diag", "-", "")), 0, 24)
  managed_identity_name    = lower(format("%s-mi-synapse-%s", var.prefix, var.environment))
  key_vault_name           = substr(lower(replace("${var.prefix}${var.environment}kv", "-", "")), 0, 24)
  key_vault_key_name       = lower(format("%s-synapse-cmk-%s", var.prefix, var.environment))
  synapse_workspace_name   = lower(format("%s-synapse-%s", var.prefix, var.environment))
  filesystem_name          = "synapse-workspace"

  default_tags = merge({
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)
}

resource "azurerm_resource_group" "synapse" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_storage_account" "primary" {
  name                       = local.primary_storage_name
  resource_group_name        = azurerm_resource_group.synapse.name
  location                   = azurerm_resource_group.synapse.location
  account_kind               = "StorageV2"
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  access_tier                = "Hot"
  https_traffic_only_enabled = true
  is_hns_enabled             = true
  min_tls_version            = "TLS1_2"

  tags = local.default_tags
}

resource "azurerm_storage_account" "diagnostics" {
  name                       = local.diagnostics_storage_name
  resource_group_name        = azurerm_resource_group.synapse.name
  location                   = azurerm_resource_group.synapse.location
  account_kind               = "StorageV2"
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  tags = local.default_tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "workspace" {
  name               = local.filesystem_name
  storage_account_id = azurerm_storage_account.primary.id
}

resource "azurerm_user_assigned_identity" "synapse" {
  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.synapse.name
  location            = azurerm_resource_group.synapse.location
  tags                = local.default_tags
}

resource "azurerm_key_vault" "synapse" {
  name                          = local.key_vault_name
  location                      = azurerm_resource_group.synapse.location
  resource_group_name           = azurerm_resource_group.synapse.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = true

  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
  }

  tags = local.default_tags
}

resource "azurerm_key_vault_access_policy" "administrator" {
  key_vault_id = azurerm_key_vault.synapse.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Create",
    "Get",
    "Delete",
    "Purge",
    "Recover",
    "GetRotationPolicy",
    "SetRotationPolicy"
  ]
}

resource "azurerm_key_vault_access_policy" "synapse_identity" {
  key_vault_id = azurerm_key_vault.synapse.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.synapse.principal_id

  key_permissions = [
    "Get",
    "UnwrapKey",
    "WrapKey"
  ]
}

resource "azurerm_key_vault_key" "synapse" {
  name         = local.key_vault_key_name
  key_vault_id = azurerm_key_vault.synapse.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["unwrapKey", "wrapKey"]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P2Y"
    notify_before_expiry = "P30D"
  }

  depends_on = [azurerm_key_vault_access_policy.administrator]
}

resource "azurerm_role_assignment" "synapse_storage_data" {
  scope                = azurerm_storage_account.primary.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.synapse.principal_id
}

resource "azurerm_synapse_workspace" "main" {
  name                                 = local.synapse_workspace_name
  resource_group_name                  = azurerm_resource_group.synapse.name
  location                             = azurerm_resource_group.synapse.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.workspace.id
  sql_administrator_login              = var.synapse_sql_administrator_login
  sql_administrator_login_password     = var.synapse_sql_administrator_password
  managed_virtual_network_enabled      = true
  data_exfiltration_protection_enabled = true

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.synapse.id]
  }

  customer_managed_key {
    key_name                  = azurerm_key_vault_key.synapse.name
    key_versionless_id        = azurerm_key_vault_key.synapse.versionless_id
    user_assigned_identity_id = azurerm_user_assigned_identity.synapse.id
  }

  tags = local.default_tags

  depends_on = [
    azurerm_role_assignment.synapse_storage_data,
    azurerm_key_vault_access_policy.synapse_identity
  ]
}
