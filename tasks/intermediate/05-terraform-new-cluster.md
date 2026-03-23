# Task 5: Terraform — Add a New Cluster Environment

**Level:** Intermediate

**Objective:** Add a fourth cluster environment (e.g., `qa`) by extending the Terraform configuration and deploying applications to it.

## Context

The current setup has 3 environments: dev, staging, gitops. Adding a new environment requires:
1. Adding to the `environments` map in Terraform
2. Creating a new workspace
3. Creating the application directory for ArgoCD
4. Updating the ArgoCD ApplicationSet template

## Steps

### Part A: Extend the Terraform Variables

1. Create a feature branch:

   ```bash
   git checkout -b feature/qa-environment
   ```

2. Open `values.auto.tfvars` and add a `qa` entry to the `environments` map:

   ```hcl
   qa = {
     node_cidr          = "10.40.0.0/17"
     range_base         = "172.20.0.0/17"
     master_cidr_offset = 3
   }
   ```

   Explain why these CIDRs don't overlap with existing environments:
   - Node CIDR: `10.40.x.x` (dev=10.10, staging=10.20, gitops=10.30)
   - Range base: `172.20.x.x` (dev=172.16, staging=172.17, gitops=172.18)
   - Master offset: `3` (dev=0, staging=1, gitops=2)

### Part B: Understand What Terraform Will Create

3. Open `shared-network.tf` and trace what happens for a new environment:
   - A new subnet `gke-subnet-qa` in the shared VPC
   - Secondary IP ranges for pods and services
   - The subnet is added to the existing VPC (no VPC recreation)

4. Open `gke.tf` and trace:
   - A new cluster `qa-cluster` will be created
   - It uses the same module, same node pool config
   - The master CIDR will be `172.19.3.0/28`

5. Open `locals.tf`:
   - `remote_workspaces` will now include `qa` (it filters out gitops)
   - ArgoCD will discover the qa cluster

### Part C: Create the Workspace and Plan

6. Initialize and create the workspace:

   ```bash
   terraform workspace new qa
   terraform plan -out=qa.tfplan
   ```

7. Review the plan:
   - What resources will be created?
   - How many total resources?
   - Is anything being destroyed?

### Part D: Create the Application Directory

8. Create the application directory with a subset of apps:

   ```bash
   mkdir -p gke-applications/qa
   ```

9. Copy essential apps from dev (not all apps — QA might need fewer):

   ```bash
   for app in istio-base istiod istio-gateway cert-manager external-secrets; do
     cp gke-applications/dev/${app}.yaml gke-applications/qa/${app}.yaml
     sed -i '' 's/cluster_env: dev/cluster_env: qa/' gke-applications/qa/${app}.yaml
   done
   ```

10. Verify the files look correct:

    ```bash
    grep cluster_env gke-applications/qa/*.yaml
    ```

### Part E: Update ArgoCD to Manage the New Cluster

11. Open `templates/apps-values.yaml`. The ApplicationSet template uses a variable for cluster names. This is rendered in `locals.tf` using:

    ```hcl
    templatefile("${path.module}/templates/apps-values.yaml", {
      clusters = keys(var.environments)
    })
    ```

    Since `qa` is now in `var.environments`, it will automatically get an ApplicationSet.

12. Open `eso.tf` — a new ExternalSecret and GCP Secret Manager secret will be created for the qa cluster credentials so ArgoCD can connect.

### Part F: The Apply Order

13. If you were to apply this for real, the order would be:
    1. `terraform workspace select gitops && terraform apply` — Creates the QA subnet, ArgoCD ApplicationSet, ESO secret
    2. `terraform workspace select qa && terraform apply` — Creates the QA cluster
    3. ArgoCD automatically deploys apps from `gke-applications/qa/`

## Key Concepts

- Adding an environment = extend the `environments` map + new workspace + app directory
- CIDRs must not overlap with existing environments
- The gitops workspace must be applied first (creates shared network resources)
- ArgoCD ApplicationSets auto-discover new cluster app directories
- ESO handles credential sync for ArgoCD to connect to the new cluster

## Cleanup

```bash
terraform workspace select dev
terraform workspace delete qa
git checkout master
git branch -d feature/qa-environment
```

**Warning:** Do NOT run `terraform apply` during this exercise.
