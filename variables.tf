variable "prefix" {
  description = "Short prefix used for all resources; should be unique per environment."
  type        = string
}

variable "location" {
  description = "Azure region where all resources will be created."
  type        = string
  default     = "usgovvirginia"
}

variable "environment" {
  description = "Environment name used for tagging (e.g., dev, test, prod)."
  type        = string
  default     = "dev"
}

variable "azure_environment" {
  description = "Azure cloud environment to target (e.g., public, usgovernment, china)."
  type        = string
  default     = "usgovernment"
}

variable "tags" {
  description = "Common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "vnet_address_space" {
  description = "Address space for the virtual network that hosts private endpoints."
  type        = list(string)
  default     = ["10.60.0.0/16"]
}

variable "private_endpoint_subnet_prefix" {
  description = "Address prefix allocated to the subnet that will host all private endpoints."
  type        = string
  default     = "10.60.10.0/24"
}

variable "jumpbox_subnet_prefix" {
  description = "Address prefix allocated to the subnet that will host the jump box virtual machine."
  type        = string
  default     = "10.60.20.0/24"
}

variable "jumpbox_admin_username" {
  description = "Admin username for the jump box virtual machine."
  type        = string
  default     = "azureuser"
}

variable "jumpbox_admin_ssh_public_key" {
  description = "SSH public key (OpenSSH format) used to secure access to the jump box virtual machine."
  type        = string
}

variable "bastion_subnet_prefix" {
  description = "Address prefix allocated to the subnet reserved for Azure Bastion (must be /26 or larger)."
  type        = string
  default     = "10.60.30.0/26"
}

variable "enable_private_dns_zones" {
  description = "Controls whether Azure Private DNS zones and links are created for private endpoints. Disable when DNS will be managed externally."
  type        = bool
  default     = true
}

variable "existing_user_assigned_identity" {
  description = "Optional details for an existing user-assigned managed identity to reuse. Leave null to create a new identity."
  type = object({
    name                = string
    resource_group_name = string
  })
  default = null
}

variable "existing_key_vault" {
  description = "Optional details for an existing Key Vault to reuse. Leave null to create a new Key Vault."
  type = object({
    name                = string
    resource_group_name = string
  })
  default = null
}

variable "existing_key_vault_key" {
  description = "Optional details for an existing Key Vault key to reuse. Provide only when also supplying existing_key_vault."
  type = object({
    name = string
  })
  default = null
}

variable "synapse_sql_administrator_login" {
  description = "Synapse SQL administrator login name."
  type        = string
}

variable "synapse_sql_administrator_password" {
  description = "Synapse SQL administrator login password."
  type        = string
  sensitive   = true
}
