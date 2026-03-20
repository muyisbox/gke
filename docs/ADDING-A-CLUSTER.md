# Adding a New Cluster

This guide walks through adding a fourth cluster (e.g., `prod`) to the platform. The process involves five areas: networking, Terraform locals, GKE provisioning, ArgoCD registration, and application definitions.

---

## Overview of Changes

| Step | What | File(s) |
|------|------|---------|
| 1 | Add subnet and secondary ranges | `shared-network.tf` |
| 2 | Add workspace to locals | `locals.tf` |
| 3 | Terraform creates the cluster | `gke.tf` (no change needed — uses `terraform.workspace`) |
| 4 | Add cluster to ArgoCD cluster map | `locals.tf` |
| 5 | ESO creates cluster secret | `eso.tf` (no change needed — driven by `local.eso_managed_clusters`) |
| 6 | Create app definitions directory | `gke-applications/prod/` |
| 7 | Create Terraform workspace | CLI |
| 8 | Apply | CLI |

---

## Step 1: Add a Subnet

Edit `shared-network.tf`. In the `subnets` list of the `module "shared-network"` block, add a new entry:

```hcl
{
  subnet_name           = "gke-subnet-prod"
  subnet_ip             = "10.40.0.0/17"
  subnet_region         = var.region
  subnet_private_access = true
},
```

In the `secondary_ranges` map, add:

```hcl
"gke-subnet-prod" = [
  {
    range_name    = "prod-pods"
    ip_cidr_range = "172.19.0.0/18"
  },
  {
    range_name    = "prod-services"
    ip_cidr_range = "172.19.64.0/18"
  },
]
```

Choose non-overlapping CIDRs. Existing ranges:

| Cluster | Node | Pods | Services |
|---------|------|------|----------|
| dev | 10.10.0.0/17 | 172.16.0.0/18 | 172.16.64.0/18 |
| staging | 10.20.0.0/17 | 172.17.0.0/18 | 172.17.64.0/18 |
| gitops | 10.30.0.0/17 | 172.18.0.0/18 | 172.18.64.0/18 |

---

## Step 2: Update locals.tf

### Add to `master_cidr_offsets`

```hcl
master_cidr_offsets = {
  dev     = "0"
  staging = "1"
  gitops  = "2"
  prod    = "3"   # ← add this
}
```

This determines the master plane CIDR: `172.19.3.0/28`.

### Add `prod` to `cluster_types` if you want Terraform to loop over it

```hcl
cluster_types = toset(["gitops", "dev", "staging", "prod"])
```

Note: `cluster_types` is currently only used if you add loops in the future. The cluster itself is provisioned using `terraform.workspace`, so the workspace name IS the cluster type.

---

## Step 3: GKE Cluster

No changes to `gke.tf` are required. The cluster name, subnet, and master CIDR are all derived from `terraform.workspace`. When you create a `prod` workspace and apply, it automatically provisions `prod-cluster` on `gke-subnet-prod` with master CIDR `172.19.3.0/28`.

To customize node pools for prod (e.g., larger machines), create a workspace-conditional block:

```hcl
node_pools = terraform.workspace == "prod" ? [
  {
    name         = "node-pool-01"
    machine_type = "e2-standard-8"   # larger for prod
    min_count    = 2
    max_count    = 10
    spot         = false
    disk_size_gb = 50
    disk_type    = "pd-ssd"
    image_type   = "COS_CONTAINERD"
    auto_repair  = true
    auto_upgrade = true
    preemptible  = false
    initial_node_count = 2
  }
] : [
  # ... existing node pool definition
]
```

---

## Step 4: Register with ArgoCD

Edit `locals.tf` to include `prod` in the ArgoCD cluster map. Currently `argocd_clusters` is built dynamically from data sources. To add prod:

### 4a. Add a data source for the prod cluster in `argocd.tf`

```hcl
data "google_container_cluster" "prod" {
  count    = terraform.workspace == "gitops" ? 1 : 0
  name     = "prod-cluster"
  location = var.region
  project  = var.project_id
}
```

Add it to the `remote` data source list (or add it explicitly like gitops cluster). The existing pattern in `argocd.tf` uses a dynamic API call to discover clusters — prod will be discovered automatically once it exists.

### 4b. The `eso_managed_clusters` local already handles this

Because `eso_managed_clusters` filters `argocd_clusters` to exclude `gitops`, any cluster you add to `argocd_clusters` (dev, staging, prod, etc.) automatically gets:
- A GCP Secret Manager secret (`argocd-cluster-prod`)
- An ExternalSecret to sync the credentials to ArgoCD

No changes to `eso.tf` are needed.

---

## Step 5: Create Application Definitions

Create the directory and populate it with app definitions:

```bash
mkdir gke-applications/prod
```

Start by copying from an existing environment:

```bash
cp gke-applications/staging/*.yaml gke-applications/prod/
```

Update `cluster_env` in every file:

```bash
# On macOS
sed -i '' 's/cluster_env: staging/cluster_env: prod/' gke-applications/prod/*.yaml

# On Linux
sed -i 's/cluster_env: staging/cluster_env: prod/' gke-applications/prod/*.yaml
```

Then review each file and adjust versions, replica counts, and resource requests as appropriate for prod.

**Important naming rules in each YAML:**

```yaml
name: my-app          # Must be unique within the cluster; becomes the Helm release name
chart: my-chart
repoURL: https://...
targetRevision: "1.2.3"
namespace: my-ns      # Namespace to deploy into; created automatically by ArgoCD
cluster_env: prod     # Informational label only — does not affect routing
```

---

## Step 6: Create and Apply the Workspace

```bash
# Initialize (only needed once)
terraform init -upgrade

# Create workspace
terraform workspace new prod

# Plan — review what will be created
terraform plan -out prod.tfplan

# Apply
terraform apply prod.tfplan
```

Apply order:
1. Apply `gitops` workspace first (creates shared network and adds prod to ArgoCD)
2. Apply `prod` workspace (creates the cluster, writes credentials to Secret Manager)
3. ESO syncs credentials within 1 hour; ArgoCD then deploys all apps in `gke-applications/prod/`

To force ESO to sync immediately (without waiting 1 hour):

```bash
# Connect to gitops cluster
gcloud container clusters get-credentials gitops-cluster --region us-central1 --project cluster-dreams

# Annotate the ExternalSecret to trigger immediate refresh
kubectl annotate externalsecret prod-cluster-secret \
  force-sync=$(date +%s) \
  -n argocd --overwrite
```

---

## Step 7: Update CI/CD Pipelines (if scheduled destroy/recreate is wanted)

If prod should also be destroyed nightly:

Edit `cicd/cloudbuild-destroy.yaml` and add a destroy step for prod (follow the existing pattern for dev/staging).

Edit `cicd/cloudbuild-create.yaml` and add a create step for prod.

If prod should run 24/7, no CI/CD changes are needed.

---

## Step 8: Verify

```bash
# Connect to gitops cluster
gcloud container clusters get-credentials gitops-cluster --region us-central1 --project cluster-dreams

# Check that ArgoCD registered the new cluster
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster

# Check that ApplicationSet was created
kubectl get applicationset -n argocd

# Check that apps are being deployed
kubectl get applications -n argocd | grep prod

# Connect to prod cluster and verify workloads
gcloud container clusters get-credentials prod-cluster --region us-central1 --project cluster-dreams
kubectl get pods -A
```

---

## Checklist

- [ ] Subnet added to `shared-network.tf` with unique CIDRs
- [ ] Master CIDR offset added to `locals.tf`
- [ ] `gke-applications/prod/` directory created with app definitions
- [ ] `cluster_env` updated to `prod` in all YAML files
- [ ] Terraform workspace `prod` created
- [ ] Gitops workspace applied (to create Secret Manager secret + ExternalSecret)
- [ ] Prod workspace applied (to create cluster + write credentials to Secret Manager)
- [ ] ArgoCD shows prod cluster as registered
- [ ] All apps show Synced/Healthy in ArgoCD
