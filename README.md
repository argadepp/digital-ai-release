# Digital.ai Release + GitHub Actions + Terraform + Azure POC

This repository provisions an Azure Resource Group using Terraform and GitHub Actions. GitHub Actions authenticates to Azure with OpenID Connect (OIDC), stores Terraform state in Azure Blob Storage, generates a plan, waits for a protected-environment approval, and applies the reviewed plan.

## Architecture

```text
Push to master
    |
    v
GitHub Actions - Terraform Plan
    |  OIDC authentication
    |  terraform fmt / init / validate / plan
    |  Azure Blob remote state
    v
Short-lived Terraform plan artifact
    |
    v
GitHub Environment approval: azure-apply
    |
    v
GitHub Actions - Terraform Apply
    |
    v
Azure Resource Group
```

Jenkins remains optional for a later Digital.ai Release integration. It is not used by this Terraform deployment workflow.

## Repository layout

```text
.
├── .github/workflows/terraform-azure.yml
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── Jenkinsfile
└── jenkins/Dockerfile
```

## 1. Configure GitHub Actions variables

In **GitHub repository → Settings → Secrets and variables → Actions → Variables**, add these repository variables:

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID` | Microsoft Entra application / service principal client ID |
| `AZURE_TENANT_ID` | Microsoft Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `TFSTATE_STORAGE_ACCOUNT` | Existing Azure Storage Account name |
| `TFSTATE_CONTAINER` | Existing Blob container name |

These are identifiers, not passwords. Do not add a client secret; this workflow uses OIDC.

The backend state key is set in the workflow to `digital-ai-release/dev.tfstate`.

## 2. Configure Azure identity and role assignments

Create or reuse a Microsoft Entra application and its service principal. The application must have a federated identity credential for the GitHub Actions workflow.

This repository uses GitHub's immutable OIDC subject format. Its repository owner ID is `90461882` and repository ID is `1451077215`. Add **two** federated credentials to the same Entra application:

### Plan job — master branch

Create a federated credential with:

- Issuer: `https://token.actions.githubusercontent.com`
- Audience: `api://AzureADTokenExchange`
- Subject: `repo:argadepp@90461882/digital-ai-release@1451077215:ref:refs/heads/master`

### Apply job — protected GitHub Environment

Create a second federated credential with:

- Issuer: `https://token.actions.githubusercontent.com`
- Audience: `api://AzureADTokenExchange`
- Subject: `repo:argadepp@90461882/digital-ai-release@1451077215:environment:azure-apply`

The apply job uses the `azure-apply` GitHub Environment, so its OIDC subject is different from the plan job's branch subject. The two credentials are both required.

You can create federated credentials in **Azure Portal → Microsoft Entra ID → App registrations → your application → Certificates & secrets → Federated credentials → Add credential → GitHub Actions deploying Azure resources**. If the portal's preset does not show the immutable subject format, enter the exact subject above using the custom issuer/audience/subject option or Azure CLI.

### Azure RBAC permissions

Assign the service principal:

1. **Contributor** at the subscription scope (needed for this initial Terraform configuration to create a Resource Group). This is broad; use a dedicated lab subscription. For production, define a least-privilege custom role.
2. **Storage Blob Data Contributor** scoped to the state container (or, if necessary, the storage account) so Terraform can read/write the state blob and use blob leases for state locking.

Example commands (run as an administrator with permission to assign roles; replace placeholders):

```bash
SUBSCRIPTION_ID="<subscription-id>"
SP_OBJECT_ID="<service-principal-object-id>"
STATE_RESOURCE_GROUP="<storage-account-resource-group>"
STATE_STORAGE_ACCOUNT="<storage-account-name>"
STATE_CONTAINER="<container-name>"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$STATE_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STATE_STORAGE_ACCOUNT/blobServices/default/containers/$STATE_CONTAINER"
```

Allow a few minutes for role assignments to propagate.

## 3. Protect the apply job with GitHub Environment approval

1. Open **Settings → Environments** in this repository.
2. Create an environment named exactly `azure-apply`.
3. Add yourself (or another trusted maintainer) as a required reviewer.
4. Enable **Prevent self-review** if you want a different person to approve the deployment.
5. Restrict deployment branches to `master`.

The plan job runs first. The apply job waits for approval before it can access the protected environment and its OIDC trust.

## 4. Terraform remote backend

The Terraform configuration contains an `azurerm` backend configured for OIDC and Microsoft Entra authentication:

- Storage account and container names are supplied to `terraform init` from GitHub repository variables.
- State key: `digital-ai-release/dev.tfstate`.
- Blob leases provide state locking.
- The backend uses Microsoft Entra data-plane authentication; no storage account access key is stored in GitHub.

The storage account and container must already exist before the workflow runs. Keep public blob access disabled and enable appropriate storage network restrictions.

## 5. Run the workflow

The workflow runs automatically when changes are pushed to `master` under `terraform/**` or the workflow file. You can also start it from **Actions → Azure Resource Group - Terraform → Run workflow** on `master`.

Expected stages:

1. Terraform format check.
2. Terraform init against the Azure Blob backend.
3. Terraform validate.
4. Terraform plan and a resource-count summary.
5. Short-lived plan artifact upload.
6. Manual approval in the `azure-apply` environment.
7. Apply the reviewed plan and display outputs.

The current Terraform configuration creates Resource Group `rg-dai-demo-dev` in `Central India`, tagged as `DEV`.

## 6. Important security notes

- This repository is currently public. Terraform plan artifacts can contain sensitive values. The current Resource Group-only plan has no configured secrets, but **make the repository private before adding infrastructure that handles credentials, connection strings, private values, or other sensitive data**.
- The plan artifact is retained for one day only.
- Never commit Terraform state, plan files, client secrets, access keys, or secret tfvars.
- Commit `.terraform.lock.hcl` after the first successful local or workflow initialization to pin provider selections.
- Keep the state storage account private and grant the workflow identity only the required data-plane role on the state container.
- Do not configure a second pipeline to apply the same Terraform state concurrently. The workflow concurrency group and Azure Blob state lock help prevent overlapping operations.

## 7. Next phase: Digital.ai Release

Later, Digital.ai Release can initiate this GitHub Actions workflow, provide a governed approval process, and capture the deployment result. Avoid running both a direct push-triggered apply and a Release-triggered apply for the same change.

## References

- [GitHub: Configure OpenID Connect in Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure)
- [HashiCorp: AzureRM backend](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Microsoft: Store Terraform state in Azure Storage](https://learn.microsoft.com/en-us/azure/terraform/terraform-backend)
