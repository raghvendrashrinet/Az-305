## Azure Landing Zone IaC Accelerator with Terraform and GitHub Actions 
### 🔹 Typical Project Setup
#### 1. Repository Structure
A common layout for a Terraform-based landing zone accelerator might look like:
```text
/infra
  ├── main.tf             # Root Terraform configuration
  ├── modules/            # Reusable Terraform modules (network, identity, policies)
  ├── variables.tf        # Input variables
  ├── terraform.tfvars    # Environment-specific values
/.github
  └── workflows/
      └── deploy.yml      # GitHub Actions pipeline definition

```
- main.tf: orchestrates modules for networking, identity, governance, monitoring, etc.

- modules/: encapsulates reusable building blocks (hub-spoke VNet, RBAC, policies).

- variables.tf / terraform.tfvars: define parameters for different environments (dev, test, prod).

- deploy.yml: GitHub Actions workflow that automates Terraform init/plan/apply.

#### 2. Terraform Modules in Action
Each module represents a piece of the landing zone:

- Networking: Hub-spoke topology, subnets, NSGs, firewalls.

- Identity: Azure AD integration, RBAC assignments, managed identities.

- Governance: Policy definitions, resource locks, tagging strategy.

- Monitoring: Log Analytics, diagnostic settings, alerts.

The accelerator provides these modules pre-built, so teams can quickly assemble a compliant environment.

#### 3. GitHub Actions Deployment Pipeline
A typical workflow (deploy.yml) might look like:
```yaml
name: Deploy Azure Landing Zone

on:
  push:
    branches: [ main ]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repo
        uses: actions/checkout@v3

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2

      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        run: terraform plan -var-file=terraform.tfvars

      - name: Terraform Apply
        run: terraform apply -auto-approve -var-file=terraform.tfvars
```
- Trigger: Runs on every push to main.

- Azure Login: Authenticates with a service principal stored in GitHub Secrets.

- Terraform steps: Initialize backend, plan changes, and apply them to Azure.

#### 4. Workflow in Practice
1. Developer commits changes to Terraform files (e.g., adding a new subnet or policy).

2. GitHub Actions pipeline runs automatically.

3. Terraform init/plan/apply executes against Azure, provisioning or updating resources.

4. Landing zone modules ensure consistent governance, networking, and monitoring across environments.
