# Terraform Synapse Environment (Azure Government)

This project provisions a minimal Azure Synapse Analytics workspace in Azure Government with customer-managed keys and private networking enforced through Azure Private Endpoints. The deployment includes:

- Azure resource group
- Virtual network and dedicated subnet for private endpoints
- ADLS Gen2 storage account for Synapse primary storage
- Secondary storage account for diagnostics
- User-assigned managed identity for the workspace
- Azure Key Vault and RSA key for workspace encryption
- Synapse workspace configured with system-assigned + user-assigned managed identity and CMK
- Private endpoints with optional Private DNS zones for storage, Key Vault, and Synapse SQL/Dev endpoints

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) 1.5+ installed
- Azure CLI authenticated against the appropriate US Gov subscription (`az cloud set --name AzureUSGovernment`)
- Permissions to create resources in the target subscription (resource group owner, user access administrator, Key Vault administrator, etc.)

## Configuration

Key input variables are declared in `variables.tf`. Provide values via `terraform.tfvars` (a sample is already present) or your preferred method.

Networking defaults can be overridden as required:

```hcl
vnet_address_space              = ["10.60.0.0/16"]
private_endpoint_subnet_prefix  = "10.60.10.0/24"
```

```hcl
prefix                             = "synapsetest"
location                           = "usgovvirginia"
azure_environment                  = "usgovernment"
synapse_sql_administrator_login    = "synapseadmin"
synapse_sql_administrator_password = "ReplaceWithStrongPassword123!"
```

> **Security tip:** replace the sample admin password with a strong secret and never commit real credentials.

### Feature toggles and reuse options

- `enable_private_dns_zones` controls whether Terraform creates the Private DNS zones/linkages for each private endpoint (default `true`). Set this to `false` when your organisation manages the required `privatelink` records outside of this deployment. Without the zones you must configure name resolution manually so clients resolve the private endpoint IPs.
- `existing_user_assigned_identity`, `existing_key_vault`, and `existing_key_vault_key` let you reuse pre-created platform resources. Provide the object values (name/resource group, and key name) when reuse is required; leave them `null` to let Terraform create new resources.

> **Private networking:** All services disable public network access and expose data planes solely through private endpoints. Run Terraform from an execution environment that has line-of-sight into the virtual network (for example, an Azure DevOps self-hosted agent joined to the VNet, or an Azure VM/bastion inside the network). Data plane operations such as creating the Data Lake filesystem or Key Vault keys require access through the private endpoints.

If you need to expose the environment temporarily for bootstrapping or break-glass scenarios, either run Terraform from within the VNet or adjust the firewall/`public_network_access_enabled` settings manually and revert once finished.

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
