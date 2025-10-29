# Terraform Synapse Environment (Azure Government)

This project provisions a minimal Azure Synapse Analytics workspace in Azure Government with customer-managed keys. The deployment includes:

- Azure resource group
- ADLS Gen2 storage account for Synapse primary storage
- Secondary storage account for diagnostics
- User-assigned managed identity for the workspace
- Azure Key Vault and RSA key for workspace encryption
- Synapse workspace configured with system-assigned + user-assigned managed identity and CMK

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.5+ installed
- Azure CLI authenticated against the appropriate US Gov subscription (`az cloud set --name AzureUSGovernment`)
- Permissions to create resources in the target subscription (resource group owner, user access administrator, Key Vault administrator, etc.)

## Configuration

Key input variables are declared in `variables.tf`. Provide values via `terraform.tfvars` (a sample is already present) or your preferred method.

```hcl
prefix                             = "synapsetest"
location                           = "usgovvirginia"
azure_environment                  = "usgovernment"
synapse_sql_administrator_login    = "synapseadmin"
synapse_sql_administrator_password = "ReplaceWithStrongPassword123!"
```

> **Security tip:** replace the sample admin password with a strong secret and never commit real credentials.

If you need to allow client access to the serverless SQL endpoint, add Synapse firewall rules (e.g., `azurerm_synapse_firewall_rule`) or configure private endpoints as required.

## Usage

Run the following commands from the repository root:

```powershell
terraform fmt
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

The apply step will output useful identifiers (resource group name, workspace name, managed identity principal ID, key vault URI). Store them for downstream configuration.

## Cleanup

To remove all deployed resources:

```powershell
terraform destroy
```

Review the plan carefully before confirming the destroy operation.

## Notes

- The Key Vault firewall is temporarily opened during provisioning (`default_action = "Allow"`). If you need a locked-down posture, update the network ACLs after deployment to restrict access to approved IP ranges or private endpoints.
- The generated RSA key uses a 2048-bit size to satisfy Synapse CMK requirements. Adjust the naming convention via `locals.key_vault_key_name` if necessary.
- `.terraform.lock.hcl` is expected to be checked into version control for provider determinism; do not delete it after `terraform init`.
