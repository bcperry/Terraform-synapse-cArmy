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
  virtual_network_name     = lower(format("%s-vnet-%s", var.prefix, var.environment))
  private_endpoint_subnet  = "private-endpoints"

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

resource "azurerm_virtual_network" "synapse" {
  name                = local.virtual_network_name
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  address_space       = var.vnet_address_space

  tags = local.default_tags
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = local.private_endpoint_subnet
  resource_group_name               = azurerm_resource_group.synapse.name
  virtual_network_name              = azurerm_virtual_network.synapse.name
  address_prefixes                  = [var.private_endpoint_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

# Private DNS zones for US Government cloud endpoints
resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "storage_dfs" {
  name                = "privatelink.dfs.core.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "synapse_sql" {
  name                = "privatelink.sql.azuresynapse.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "synapse_dev" {
  name                = "privatelink.dev.azuresynapse.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "${local.virtual_network_name}-blob-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_dfs" {
  name                  = "${local.virtual_network_name}-dfs-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_dfs.name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "${local.virtual_network_name}-kv-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "synapse_sql" {
  name                  = "${local.virtual_network_name}-sql-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_sql.name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "synapse_dev" {
  name                  = "${local.virtual_network_name}-dev-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_dev.name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_storage_account" "primary" {
  name                          = local.primary_storage_name
  resource_group_name           = azurerm_resource_group.synapse.name
  location                      = azurerm_resource_group.synapse.location
  account_kind                  = "StorageV2"
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  access_tier                   = "Hot"
  https_traffic_only_enabled    = true
  is_hns_enabled                = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = true # TEMP: revert to false after private endpoints succeed

  tags = local.default_tags
}

resource "azurerm_storage_account" "diagnostics" {
  name                          = local.diagnostics_storage_name
  resource_group_name           = azurerm_resource_group.synapse.name
  location                      = azurerm_resource_group.synapse.location
  account_kind                  = "StorageV2"
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = true # TEMP: revert to false after private endpoints succeed

  tags = local.default_tags
}

resource "azurerm_private_endpoint" "primary_blob" {
  name                = "${var.prefix}-pe-primary-blob-${var.environment}"
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-primary-blob"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.primary.id
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "storage-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = local.default_tags
}

resource "azurerm_private_endpoint" "primary_dfs" {
  name                = "${var.prefix}-pe-primary-dfs-${var.environment}"
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-primary-dfs"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.primary.id
    subresource_names              = ["dfs"]
  }

  private_dns_zone_group {
    name                 = "storage-dfs"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_dfs.id]
  }

  tags = local.default_tags
}

resource "azurerm_private_endpoint" "diagnostics_blob" {
  name                = "${var.prefix}-pe-diag-blob-${var.environment}"
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-diagnostics-blob"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.diagnostics.id
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "diagnostics-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = local.default_tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "workspace" {
  name               = local.filesystem_name
  storage_account_id = azurerm_storage_account.primary.id

  depends_on = [azurerm_private_endpoint.primary_dfs]
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
  public_network_access_enabled = true # TEMP: revert to false after private endpoints succeed

  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow" # TEMP: change back to Deny when private endpoints wired
  }

  tags = local.default_tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "${var.prefix}-pe-kv-${var.environment}"
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-kv"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_key_vault.synapse.id
    subresource_names              = ["Vault"]
  }

  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
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

  depends_on = [
    azurerm_key_vault_access_policy.administrator,
    azurerm_private_endpoint.key_vault
  ]
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
  public_network_access_enabled        = false

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

resource "azurerm_private_endpoint" "synapse_sql" {
  name                = "${var.prefix}-pe-sql-${var.environment}"
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-synapse-sql"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_synapse_workspace.main.id
    subresource_names              = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "synapse-sql"
    private_dns_zone_ids = [azurerm_private_dns_zone.synapse_sql.id]
  }

  tags = local.default_tags

  depends_on = [azurerm_synapse_workspace.main]
}

resource "azurerm_private_endpoint" "synapse_dev" {
  name                = "${var.prefix}-pe-dev-${var.environment}"
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-synapse-dev"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_synapse_workspace.main.id
    subresource_names              = ["Dev"]
  }

  private_dns_zone_group {
    name                 = "synapse-dev"
    private_dns_zone_ids = [azurerm_private_dns_zone.synapse_dev.id]
  }

  tags = local.default_tags

  depends_on = [azurerm_synapse_workspace.main]
}
