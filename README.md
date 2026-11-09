# Digital.ai Release + Jenkins + Terraform + Azure POC

This repository demonstrates an initial Infrastructure as Code workflow that creates an Azure Resource Group with Terraform. Jenkins checks out the repository, validates Terraform, creates a plan, waits for manual approval, then applies the saved plan.

## Architecture

```text
GitHub push -> GitHub webhook (HTTPS tunnel) -> Jenkins Pipeline
             -> Terraform fmt/init/validate -> plan -> approval -> apply
             -> Azure Resource Group
```

For this first iteration, approval is a Jenkins input gate. Digital.ai Release can become the governed release orchestrator in the next phase.

## Repository layout

```text
.
├── Jenkinsfile
├── jenkins/Dockerfile
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars.example
```

## 1. Azure service principal

Sign in and select your intended subscription:

```bash
az login
az account show --query "{name:name,id:id,tenant:tenantId}" -o table
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

For a disposable lab only, create a service principal with Contributor at subscription scope:

```bash
az ad sp create-for-rbac \
  --name "sp-jenkins-terraform-demo" \
  --role Contributor \
  --scopes "/subscriptions/<YOUR_SUBSCRIPTION_ID>"
```

Securely save the returned `appId`, `password`, and `tenant`. Identity creation and role assignment require appropriate Entra ID/Azure permissions. Subscription-scope Contributor is broad; use a dedicated lab subscription or a least-privilege custom role for longer-lived use.

## 2. Jenkins credentials

Create these in **Manage Jenkins → Credentials → (global) → Add Credentials**:

| ID | Kind | Value |
|---|---|---|
| `azure-sp` | Username with password | Username = appId; Password = service principal password |
| `azure-tenant-id` | Secret text | Tenant ID |
| `azure-subscription-id` | Secret text | Subscription ID |

AzureRM reads `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, and `ARM_SUBSCRIPTION_ID` from the environment. Never put these values in Git.

## 3. Jenkins image with Terraform

The `jenkins/Dockerfile` installs Terraform in a Jenkins LTS image. Merge this service configuration into your existing Compose file. Keep the Digital.ai Release service, existing volumes, and shared network unchanged:

```yaml
jenkins:
  build:
    context: ./jenkins
  image: local/jenkins-terraform:1.0
  container_name: jenkins
  restart: unless-stopped
  ports:
    - "8081:8080"
    - "50000:50000"
  volumes:
    - jenkins-home:/var/jenkins_home
  networks:
    - devops-lab
```

This assumes your Compose file already defines `jenkins-home` and `devops-lab`. Do not replace your entire Compose file with this fragment.

```bash
docker compose build jenkins
docker compose up -d jenkins
docker exec jenkins terraform version
```

## 4. Jenkins pipeline job

1. Install/enable the Jenkins GitHub plugin.
2. Create **New Item → Pipeline**, e.g. `azure-rg-terraform`.
3. Under **Build Triggers**, enable **GitHub hook trigger for GITScm polling**.
4. Under **Pipeline**, select **Pipeline script from SCM**.
5. Select Git; repository URL: `https://github.com/argadepp/digital-ai-release.git`; branch: `*/master`; script path: `Jenkinsfile`.
6. Configure Git credentials if required.
7. Save and run once manually before testing the webhook.

## 5. GitHub webhook for local Jenkins

GitHub cannot reach localhost directly. Expose Jenkins host port 8081 through a temporary HTTPS tunnel, for example:

```bash
ngrok http 8081
```

In GitHub **Settings → Webhooks → Add webhook**:

- Payload URL: `https://<your-ngrok-host>/github-webhook/`
- Content type: `application/json`
- Events: **Just the push event**
- Active: enabled

The tunnel hostname can change after restart; update the webhook when it does.

**Security:** This tunnel exposes the Jenkins web interface as well as the webhook endpoint. Keep Jenkins authentication enabled, use strong credentials, and stop the tunnel when not in use. Configure and verify webhook secret validation where supported by your Jenkins GitHub plugin configuration. This is temporary lab ingress, not a production pattern.

## 6. Terraform defaults

The default configuration creates Resource Group `rg-dai-demo-dev` in `Central India`, tagged with environment `DEV`. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` to override values. The real tfvars file is ignored by Git.

## 7. Test

1. Push a change to `master`.
2. Check GitHub **Settings → Webhooks → Recent Deliveries**.
3. Confirm the Jenkins job starts.
4. Review the archived Terraform plan in Jenkins.
5. Approve only after checking the plan.
6. Verify the Resource Group in the intended Azure subscription.

For this initial lab, state is stored in the Jenkins workspace. This is not a durable or team-safe backend. Before expanding the POC, configure an Azure Storage remote backend, state locking, access controls, and a recovery plan.

## 8. Next phase: Digital.ai Release

A future flow can be:

1. GitHub push triggers validation and Terraform plan.
2. Digital.ai Release starts/receives the release event.
3. Release approval gates the apply step.
4. Release invokes Jenkins apply and records the result.
5. A post-deployment task verifies the Resource Group.

Avoid leaving both direct GitHub-triggered apply and Release-controlled apply enabled, to prevent duplicate applies.

## Notes

- Never commit Terraform state, plan files, client secrets, or secret tfvars.
- Commit `.terraform.lock.hcl` after the first successful `terraform init` for reproducible provider selection.
- The Jenkins image uses Terraform 1.11.4; the Terraform configuration requires 1.6+ and AzureRM provider 4.x.
