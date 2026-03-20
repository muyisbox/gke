# Runbook: Common Operations

This runbook covers frequent operational tasks: connecting to clusters, running Terraform, debugging ArgoCD, and recovering from failures.

---

## Setup

### Load aliases (run once per terminal session)

```bash
source scripts/gcloud-aliases.sh
```

### Connect to a cluster

```bash
# Gitops (hub cluster)
gcloud container clusters get-credentials gitops-cluster --region us-central1 --project cluster-dreams

# Dev
gcloud container clusters get-credentials dev-cluster --region us-central1 --project cluster-dreams

# Staging
gcloud container clusters get-credentials staging-cluster --region us-central1 --project cluster-dreams

# Using alias
gke-connect gitops-cluster
```

---

## Terraform Operations

### Initialize

```bash
terraform init -upgrade
```

### Switch workspace

```bash
terraform workspace select gitops   # or dev / staging
```

### Plan and apply a specific workspace

```bash
terraform workspace select dev
terraform plan -out dev.tfplan
terraform apply dev.tfplan
```

### Apply all workspaces (same order as CI/CD)

```bash
for ws in gitops dev staging; do
  terraform workspace select $ws
  terraform plan -out ${ws}.tfplan
  terraform apply ${ws}.tfplan
done
```

### Refresh state without applying

```bash
terraform refresh
```

### Import a resource into state (e.g., after a node pool was recreated outside Terraform)

```bash
# Example: re-import dev node pool
terraform workspace select dev
terraform import \
  'module.gke.google_container_node_pool.pools["node-pool-01"]' \
  projects/cluster-dreams/locations/us-central1/clusters/dev-cluster/nodePools/node-pool-01
```

### Force-unlock state (if a previous apply left a lock)

```bash
terraform workspace select dev
terraform force-unlock LOCK_ID
```

---

## ArgoCD Operations

### Access the ArgoCD UI

```bash
# Connect to gitops cluster first
gcloud container clusters get-credentials gitops-cluster --region us-central1 --project cluster-dreams

# Port-forward
kubectl port-forward svc/argo-cd-argocd-server 8080:443 -n argocd

# Get the admin password
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

Open https://localhost:8080 (ignore the self-signed cert warning).

### List all applications

```bash
kubectl get applications -n argocd
```

### Force sync a specific app

```bash
kubectl patch application my-app-dev -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"syncStrategy":{"apply":{"force":true}}}}}'
```

Or with the ArgoCD CLI:

```bash
argocd app sync my-app-dev --force
```

### Check why an app is OutOfSync

```bash
kubectl describe application my-app-dev -n argocd
```

### List registered clusters

```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.data.name | @base64d}{"\n"}{end}'
```

### Force ESO to re-sync a cluster secret immediately

```bash
# Trigger immediate refresh (ESO normally refreshes every 1 hour)
kubectl annotate externalsecret dev-cluster-secret \
  force-sync=$(date +%s) \
  -n argocd --overwrite
```

### Manually delete and recreate ArgoCD apps helm release (if Terraform state is out of sync)

```bash
terraform workspace select gitops
terraform apply -replace='module.argocd-apps["gitops"].helm_release.this[0]'
```

---

## Cluster Debugging

### Check node status

```bash
kubectl get nodes -o wide
```

### Check why a node is NotReady

```bash
kubectl describe node NODE_NAME | grep -A 20 "Conditions:"
```

### Check kube-system pods (should never have istio.io/rev label)

```bash
# Verify kube-system does NOT have the istio label
kubectl get namespace kube-system --show-labels

# If it does, remove it immediately
kubectl label namespace kube-system istio.io/rev-
```

### Check for pods stuck in Pending/Init state

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl describe pod POD_NAME -n NAMESPACE
```

### Check PVC status (storage issues)

```bash
kubectl get pvc -A
kubectl describe pvc PVC_NAME -n NAMESPACE
```

---

## Recovering from Common Failures

### Nightly destroy left clusters in a broken state

If Cloud Build destroy ran but create failed, clusters may be partially destroyed or in an inconsistent state.

```bash
# Check what exists
gcloud container clusters list --project cluster-dreams --region us-central1

# Re-run create pipeline manually
gcloud builds triggers run terraform-create-scheduled \
  --region us-central1 \
  --project cluster-dreams

# Or apply locally
terraform workspace select dev
terraform apply -auto-approve
terraform workspace select staging
terraform apply -auto-approve
```

### ArgoCD doesn't see a cluster after it was recreated

1. Check if the Secret Manager secret was updated by Terraform:

```bash
gcloud secrets versions list argocd-cluster-dev --project cluster-dreams
gcloud secrets versions access latest --secret argocd-cluster-dev --project cluster-dreams
```

2. Force ESO to refresh:

```bash
kubectl annotate externalsecret dev-cluster-secret \
  force-sync=$(date +%s) -n argocd --overwrite
```

3. Check the ExternalSecret status:

```bash
kubectl get externalsecret dev-cluster-secret -n argocd -o yaml
```

4. Check if the ArgoCD cluster secret has the correct server address:

```bash
kubectl get secret dev-cluster-secret -n argocd -o jsonpath='{.data.server}' | base64 -d
```

### Prometheus PVCs stuck in Pending (StorageClass issue)

Delete StatefulSets and PVCs to let ArgoCD recreate with the correct StorageClass:

```bash
# Connect to the affected cluster (e.g., dev)
gcloud container clusters get-credentials dev-cluster --region us-central1 --project cluster-dreams

# Delete StatefulSets (PVCs are retained)
kubectl delete statefulset -n monitoring --all

# Delete PVCs
kubectl delete pvc -n monitoring --all

# ArgoCD will recreate everything using the values in gke-applications/dev/prometheus.yaml
# which specifies storageClassName: standard
```

### Terraform state lock after a failed apply

```bash
# Get the lock ID from the error message, then:
terraform workspace select WORKSPACE
terraform force-unlock LOCK_ID
```

### Node pool update times out in Terraform

GKE continues the rolling update even if Terraform times out. Options:

1. Wait for GKE to finish, then run `terraform apply` again (it will see nodes are already updated).
2. Run the update asynchronously:

```bash
gcloud container node-pools update node-pool-01 \
  --cluster dev-cluster \
  --region us-central1 \
  --project cluster-dreams \
  --async
```

3. If Terraform state is corrupt after a timeout, import the node pool:

```bash
terraform import \
  'module.gke.google_container_node_pool.pools["node-pool-01"]' \
  projects/cluster-dreams/locations/us-central1/clusters/dev-cluster/nodePools/node-pool-01
```

---

## GCP Quota Issues

### Check current quota usage

```bash
gcloud compute regions describe us-central1 \
  --project cluster-dreams \
  --format="table(quotas.metric, quotas.limit, quotas.usage)"
```

### SSD quota exceeded

Symptoms: PVC stuck in Pending with `Quota 'SSD_TOTAL_GB' exceeded`.

Fix: Ensure Prometheus PVCs use `storageClassName: standard` in `gke-applications/{cluster}/prometheus.yaml`. Then delete the old PVCs (see above).

If node disks are the problem, reduce `disk_size_gb` in `gke.tf` and apply — GKE will roll node pools with smaller disks.

---

## CI/CD Operations

### Submit a test build manually

```bash
source scripts/gcloud-aliases.sh
gcb-test
```

### Stream logs from an active build

```bash
gcb-logs BUILD_ID
# or
gcloud builds log BUILD_ID --stream --region us-central1 --project cluster-dreams
```

### Trigger the plan pipeline manually

```bash
gcloud builds triggers run terraform-plan-pr \
  --region us-central1 \
  --project cluster-dreams
```

### Trigger the apply pipeline manually

```bash
gcloud builds triggers run terraform-apply \
  --region us-central1 \
  --project cluster-dreams
```

---

## Cost Monitoring

### Check which clusters are running

```bash
gcloud container clusters list \
  --project cluster-dreams \
  --region us-central1 \
  --format="table(name, status, currentNodeCount)"
```

### Check node count per cluster

```bash
for cluster in dev-cluster staging-cluster gitops-cluster; do
  echo "=== $cluster ==="
  gcloud container clusters describe $cluster \
    --region us-central1 --project cluster-dreams \
    --format="value(currentNodeCount)"
done
```

### Manually trigger destroy (outside scheduled hours)

```bash
gcloud builds triggers run terraform-destroy-scheduled \
  --region us-central1 \
  --project cluster-dreams
```

### Manually trigger recreate

```bash
gcloud builds triggers run terraform-create-scheduled \
  --region us-central1 \
  --project cluster-dreams
```
