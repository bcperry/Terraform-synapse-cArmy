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
  spark_pool_name          = substr(lower(replace("${var.prefix}${var.environment}spark", "-", "")), 0, 15)
  jumpbox_subnet_name      = "jumpbox"
  jumpbox_nsg_name         = lower(format("%s-jb-nsg-%s", var.prefix, var.environment))
  jumpbox_nic_name         = lower(format("%s-jb-nic-%s", var.prefix, var.environment))
  jumpbox_vm_name          = substr(lower(format("%s-jb-%s", var.prefix, var.environment)), 0, 64)
  bastion_subnet_name      = "AzureBastionSubnet"
  bastion_public_ip_name   = lower(format("%s-bas-pip-%s", var.prefix, var.environment))
  bastion_host_name        = lower(format("%s-bas-%s", var.prefix, var.environment))
  filesystem_name          = "synapse-workspace"
  virtual_network_name     = lower(format("%s-vnet-%s", var.prefix, var.environment))
  private_endpoint_subnet  = "private-endpoints"
  enable_private_dns_zones = var.enable_private_dns_zones
  enable_jumpbox_bastion   = var.enable_jumpbox_bastion
  using_existing_identity  = var.existing_user_assigned_identity != null
  using_existing_key_vault = var.existing_key_vault != null
  using_existing_key       = var.existing_key_vault_key != null

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

resource "azurerm_subnet" "jumpbox" {
  count                = local.enable_jumpbox_bastion ? 1 : 0
  name                 = local.jumpbox_subnet_name
  resource_group_name  = azurerm_resource_group.synapse.name
  virtual_network_name = azurerm_virtual_network.synapse.name
  address_prefixes     = [var.jumpbox_subnet_prefix]
}

resource "azurerm_subnet" "bastion" {
  count                = local.enable_jumpbox_bastion ? 1 : 0
  name                 = local.bastion_subnet_name
  resource_group_name  = azurerm_resource_group.synapse.name
  virtual_network_name = azurerm_virtual_network.synapse.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

resource "azurerm_network_security_group" "jumpbox" {
  count               = local.enable_jumpbox_bastion ? 1 : 0
  name                = local.jumpbox_nsg_name
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.bastion_subnet_prefix
    destination_address_prefix = "*"
  }

  tags = local.default_tags
}

resource "azurerm_subnet_network_security_group_association" "jumpbox" {
  count = local.enable_jumpbox_bastion ? 1 : 0

  subnet_id                 = azurerm_subnet.jumpbox[count.index].id
  network_security_group_id = azurerm_network_security_group.jumpbox[count.index].id
}

resource "azurerm_network_interface" "jumpbox" {
  count               = local.enable_jumpbox_bastion ? 1 : 0
  name                = local.jumpbox_nic_name
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.jumpbox[count.index].id
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.default_tags
}

resource "azurerm_public_ip" "bastion" {
  count               = local.enable_jumpbox_bastion ? 1 : 0
  name                = local.bastion_public_ip_name
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.default_tags
}

resource "azurerm_bastion_host" "main" {
  count               = local.enable_jumpbox_bastion ? 1 : 0
  name                = local.bastion_host_name
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[count.index].id
    public_ip_address_id = azurerm_public_ip.bastion[count.index].id
  }

  tags = local.default_tags
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  count               = local.enable_jumpbox_bastion ? 1 : 0
  name                = local.jumpbox_vm_name
  resource_group_name = azurerm_resource_group.synapse.name
  location            = azurerm_resource_group.synapse.location
  size                = "Standard_B2s"
  admin_username      = var.jumpbox_admin_username
  network_interface_ids = [
    azurerm_network_interface.jumpbox[count.index].id
  ]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.jumpbox_admin_username
    public_key = var.jumpbox_admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  tags = local.default_tags
}

# Private DNS zones for US Government cloud endpoints
resource "azurerm_private_dns_zone" "storage_blob" {
  count               = local.enable_private_dns_zones ? 1 : 0
  name                = "privatelink.blob.core.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "storage_dfs" {
  count               = local.enable_private_dns_zones ? 1 : 0
  name                = "privatelink.dfs.core.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "key_vault" {
  count               = local.enable_private_dns_zones ? 1 : 0
  name                = "privatelink.vaultcore.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "synapse_sql" {
  count               = local.enable_private_dns_zones ? 1 : 0
  name                = "privatelink.sql.azuresynapse.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone" "synapse_dev" {
  count               = local.enable_private_dns_zones ? 1 : 0
  name                = "privatelink.dev.azuresynapse.usgovcloudapi.net"
  resource_group_name = azurerm_resource_group.synapse.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  count                 = local.enable_private_dns_zones ? 1 : 0
  name                  = "${local.virtual_network_name}-blob-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob[0].name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_dfs" {
  count                 = local.enable_private_dns_zones ? 1 : 0
  name                  = "${local.virtual_network_name}-dfs-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_dfs[0].name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                 = local.enable_private_dns_zones ? 1 : 0
  name                  = "${local.virtual_network_name}-kv-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "synapse_sql" {
  count                 = local.enable_private_dns_zones ? 1 : 0
  name                  = "${local.virtual_network_name}-sql-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_sql[0].name
  virtual_network_id    = azurerm_virtual_network.synapse.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "synapse_dev" {
  count                 = local.enable_private_dns_zones ? 1 : 0
  name                  = "${local.virtual_network_name}-dev-link"
  resource_group_name   = azurerm_resource_group.synapse.name
  private_dns_zone_name = azurerm_private_dns_zone.synapse_dev[0].name
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

  dynamic "private_dns_zone_group" {
    for_each = local.enable_private_dns_zones ? [1] : []
    content {
      name                 = "storage-blob"
      private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob[0].id]
    }
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

  dynamic "private_dns_zone_group" {
    for_each = local.enable_private_dns_zones ? [1] : []
    content {
      name                 = "storage-dfs"
      private_dns_zone_ids = [azurerm_private_dns_zone.storage_dfs[0].id]
    }
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

  dynamic "private_dns_zone_group" {
    for_each = local.enable_private_dns_zones ? [1] : []
    content {
      name                 = "diagnostics-blob"
      private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob[0].id]
    }
  }

  tags = local.default_tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "workspace" {
  name               = local.filesystem_name
  storage_account_id = azurerm_storage_account.primary.id

  depends_on = [azurerm_private_endpoint.primary_dfs]
}

resource "azurerm_user_assigned_identity" "synapse" {
  count               = local.using_existing_identity ? 0 : 1
  name                = local.managed_identity_name
  resource_group_name = azurerm_resource_group.synapse.name
  location            = azurerm_resource_group.synapse.location
  tags                = local.default_tags
}

data "azurerm_user_assigned_identity" "existing" {
  count               = local.using_existing_identity ? 1 : 0
  name                = var.existing_user_assigned_identity.name
  resource_group_name = var.existing_user_assigned_identity.resource_group_name
}

resource "azurerm_key_vault" "synapse" {
  count                         = local.using_existing_key_vault ? 0 : 1
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

data "azurerm_key_vault" "existing" {
  count               = local.using_existing_key_vault ? 1 : 0
  name                = var.existing_key_vault.name
  resource_group_name = var.existing_key_vault.resource_group_name
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "${var.prefix}-pe-kv-${var.environment}"
  location            = azurerm_resource_group.synapse.location
  resource_group_name = azurerm_resource_group.synapse.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-kv"
    is_manual_connection           = false
    private_connection_resource_id = local.synapse_key_vault_id
    subresource_names              = ["Vault"]
  }

  dynamic "private_dns_zone_group" {
    for_each = local.enable_private_dns_zones ? [1] : []
    content {
      name                 = "kv"
      private_dns_zone_ids = [azurerm_private_dns_zone.key_vault[0].id]
    }
  }

  tags = local.default_tags
}

resource "azurerm_key_vault_access_policy" "administrator" {
  count        = local.using_existing_key_vault ? 0 : 1
  key_vault_id = local.synapse_key_vault_id
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
  count        = local.using_existing_key_vault ? 0 : 1
  key_vault_id = local.synapse_key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = local.synapse_identity_principal_id

  key_permissions = [
    "Get",
    "UnwrapKey",
    "WrapKey"
  ]
}

resource "azurerm_key_vault_key" "synapse" {
  count        = local.using_existing_key ? 0 : 1
  name         = local.key_vault_key_name
  key_vault_id = local.synapse_key_vault_id
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

data "azurerm_key_vault_key" "existing" {
  count = local.using_existing_key ? 1 : 0
  name  = var.existing_key_vault_key.name
  key_vault_id = element(concat(
    azurerm_key_vault.synapse[*].id,
    data.azurerm_key_vault.existing[*].id,
  ), 0)

}

locals {
  synapse_identity_id = element(concat(
    azurerm_user_assigned_identity.synapse[*].id,
    data.azurerm_user_assigned_identity.existing[*].id,
  ), 0)

  synapse_identity_principal_id = element(concat(
    azurerm_user_assigned_identity.synapse[*].principal_id,
    data.azurerm_user_assigned_identity.existing[*].principal_id,
  ), 0)

  synapse_key_vault_id = element(concat(
    azurerm_key_vault.synapse[*].id,
    data.azurerm_key_vault.existing[*].id,
  ), 0)

  synapse_key_vault_uri = element(concat(
    azurerm_key_vault.synapse[*].vault_uri,
    data.azurerm_key_vault.existing[*].vault_uri,
  ), 0)

  synapse_key_versionless_id = element(concat(
    azurerm_key_vault_key.synapse[*].versionless_id,
    data.azurerm_key_vault_key.existing[*].versionless_id,
  ), 0)

  synapse_key_name = element(concat(
    azurerm_key_vault_key.synapse[*].name,
    data.azurerm_key_vault_key.existing[*].name,
  ), 0)
}

check "existing_key_requires_vault" {
  assert {
    condition     = var.existing_key_vault_key == null || var.existing_key_vault != null
    error_message = "existing_key_vault must be provided when existing_key_vault_key is supplied."
  }
}

check "jumpbox_requires_ssh_key" {
  assert {
    condition     = !local.enable_jumpbox_bastion || trim(var.jumpbox_admin_ssh_public_key) != ""
    error_message = "jumpbox_admin_ssh_public_key must be provided when enable_jumpbox_bastion is true."
  }
}

resource "azurerm_role_assignment" "synapse_storage_data" {
  scope                = azurerm_storage_account.primary.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.synapse_identity_principal_id
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
    identity_ids = [local.synapse_identity_id]
  }

  customer_managed_key {
    key_name                  = local.synapse_key_name
    key_versionless_id        = local.synapse_key_versionless_id
    user_assigned_identity_id = local.synapse_identity_id
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

  dynamic "private_dns_zone_group" {
    for_each = local.enable_private_dns_zones ? [1] : []
    content {
      name                 = "synapse-sql"
      private_dns_zone_ids = [azurerm_private_dns_zone.synapse_sql[0].id]
    }
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

  dynamic "private_dns_zone_group" {
    for_each = local.enable_private_dns_zones ? [1] : []
    content {
      name                 = "synapse-dev"
      private_dns_zone_ids = [azurerm_private_dns_zone.synapse_dev[0].id]
    }
  }

  tags = local.default_tags

  depends_on = [azurerm_synapse_workspace.main]
}

resource "azurerm_synapse_spark_pool" "dev" {
  name                 = local.spark_pool_name
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  node_size_family     = "MemoryOptimized"
  node_size            = "Small"
  node_count           = 3 # Smallest allowed fixed-size pool configuration
  spark_version        = "3.4"

  auto_pause {
    delay_in_minutes = 15 # Keep costs down by pausing quickly when idle
  }

  tags = local.default_tags

  depends_on = [azurerm_synapse_workspace.main]
}
