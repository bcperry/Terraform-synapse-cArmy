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

variable "synapse_sql_administrator_login" {
  description = "Synapse SQL administrator login name."
  type        = string
}

variable "synapse_sql_administrator_password" {
  description = "Synapse SQL administrator login password."
  type        = string
  sensitive   = true
}
