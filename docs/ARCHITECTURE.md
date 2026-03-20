# Architecture Overview

This document describes the design of the GKE multi-cluster GitOps platform.

---

## High-Level Design

```
┌─────────────────────────────────────────────────────────────────────┐
│ GitHub (muyisbox/gke)                                               │
│  ├─ Terraform IaC (*.tf)                                            │
│  ├─ App definitions (gke-applications/{cluster}/*.yaml)             │
│  └─ CI/CD pipelines (cicd/cloudbuild*.yaml)                        │
└─────────────────────┬───────────────────────────────────────────────┘
                      │  Push/PR triggers
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Google Cloud Build                                                  │
│  ├─ PR: plan all workspaces (cloudbuild-plan.yaml)                 │
│  ├─ Merge to master: apply all workspaces (cloudbuild.yaml)        │
│  ├─ 2 AM EST: destroy dev+staging (cloudbuild-destroy.yaml)        │
│  └─ 10 AM EST: recreate dev+staging (cloudbuild-create.yaml)       │
└─────────────────────┬───────────────────────────────────────────────┘
                      │  Provisions
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│ GCP Project: cluster-dreams  /  Region: us-central1                 │
│                                                                     │
│  Shared VPC: shared-gke-network                                     │
│  ├─ gke-subnet-gitops   (10.30.0.0/17)                             │
│  ├─ gke-subnet-dev      (10.10.0.0/17)                             │
│  └─ gke-subnet-staging  (10.20.0.0/17)                             │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐     │
│  │  gitops-cluster  │  │ dev-cluster  │  │ staging-cluster  │     │
│  │  (Hub / Control) │  │   (Spoke)    │  │    (Spoke)       │     │
│  │                  │  │              │  │                  │     │
│  │  ArgoCD          │──▶ All apps     │  │  All apps        │     │
│  │  ESO             │──▶              │  │                  │     │
│  │  Monitoring      │  │              │  │                  │     │
│  └──────────────────┘  └──────────────┘  └──────────────────┘     │
│                                                                     │
│  GCP Secret Manager                                                 │
│  ├─ argocd-cluster-dev      (cluster endpoint + CA cert)           │
│  └─ argocd-cluster-staging  (cluster endpoint + CA cert)           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Terraform Workspaces

Each environment is a separate Terraform workspace sharing a single GCS state bucket.

| Workspace | Cluster | State Key |
|-----------|---------|-----------|
| `gitops` | gitops-cluster | `terraform/state/gitops` |
| `dev` | dev-cluster | `terraform/state/dev` |
| `staging` | staging-cluster | `terraform/state/staging` |

**Apply order matters**: `gitops` workspace must be applied first (creates the shared VPC, Cloud NAT, and ArgoCD). Dev and staging can then be applied in any order.

---

## Networking

All clusters share one VPC (`shared-gke-network`) with one Cloud Router and one Cloud NAT — avoiding per-cluster NAT charges.

| Cluster | Node CIDR | Pod CIDR | Service CIDR | Master CIDR |
|---------|-----------|----------|--------------|-------------|
| dev | 10.10.0.0/17 | 172.16.0.0/18 | 172.16.64.0/18 | 172.19.0.0/28 |
| staging | 10.20.0.0/17 | 172.17.0.0/18 | 172.17.64.0/18 | 172.19.1.0/28 |
| gitops | 10.30.0.0/17 | 172.18.0.0/18 | 172.18.64.0/18 | 172.19.2.0/28 |

All clusters are private (nodes have no public IPs). The control plane endpoint is public but protected by GCP auth.

---

## GitOps Flow (Hub-Spoke ArgoCD)

```
GitHub repo (gke-applications/{cluster}/*.yaml)
       │
       │  Git generator polls for new/changed files
       ▼
ArgoCD ApplicationSet (running on gitops-cluster)
       │
       │  Creates one Application per YAML file found
       ▼
ArgoCD Application
       │
       │  Deploys Helm chart to target cluster
       ▼
 dev-cluster / staging-cluster / gitops-cluster
```

1. Each file in `gke-applications/{cluster}/` defines one application.
2. The `{cluster}-apps` ApplicationSet watches that directory.
3. When a file is added/changed, ArgoCD creates/updates the corresponding Application.
4. ArgoCD connects to the target cluster using credentials from Kubernetes secrets (populated by ESO for dev/staging, or directly for gitops).

---

## Secret Management (ESO)

Terraform populates GCP Secret Manager with cluster credentials. ESO reads those secrets and creates ArgoCD cluster registration secrets inside the gitops cluster.

```
Terraform apply (gitops workspace)
  └─▶ Writes cluster endpoint + CA cert to GCP Secret Manager
           │
           ▼
External Secrets Operator (on gitops-cluster)
  └─▶ Reads Secret Manager via Workload Identity
  └─▶ Creates K8s secret in argocd namespace (label: argocd.argoproj.io/secret-type=cluster)
           │
           ▼
ArgoCD detects cluster secret → registers cluster → deploys apps
```

**Why this design**: Dev and staging clusters are destroyed nightly and recreated in the morning. Their endpoints change. Terraform writes the new endpoint to Secret Manager, ESO syncs it to ArgoCD (within 1 hour), and ArgoCD reconnects automatically.

---

## Node Configuration

All clusters use the same node pool spec:

| Setting | Value |
|---------|-------|
| Machine type | e2-standard-4 (4 vCPU, 16 GB) |
| Disk | 30 GB pd-ssd |
| Image | COS_CONTAINERD |
| Spot/Preemptible | No (regular VMs for stability) |
| Min nodes | 1 |
| Max nodes | 4 (per pool) |
| Autoscaler profile | OPTIMIZE_UTILIZATION |

Node Auto-Provisioning (NAP) is enabled, allowing GKE to provision nodes of different types when workloads require it.

---

## Cost Optimization

Dev and staging clusters are destroyed every night at 2 AM EST and recreated at 10 AM EST by Cloud Scheduler → Cloud Build triggers. Only gitops runs 24/7 (it owns the shared network and ArgoCD).

Estimated savings: ~67% on dev/staging compute costs (16 hours off per day).

---

## Applications Deployed Per Cluster

All clusters run the same base stack:

| Application | Chart | Namespace | Purpose |
|-------------|-------|-----------|---------|
| external-secrets | external-secrets | external-secrets | Syncs GCP secrets to K8s |
| cert-manager | cert-manager | cert-manager | TLS certificate management |
| istio-base | base | istio-system | Istio CRDs |
| istiod | istiod | istio-system | Istio control plane |
| istio-gateway | gateway | istio-gateways | Ingress gateway |
| prometheus-monitoring | kube-prometheus-stack | monitoring | Metrics + Grafana + Alertmanager |
| loki | loki | logging | Log aggregation |
| kiali | kiali | monitoring | Istio topology visualization |
| argo-rollouts | argo-rollouts | argo-rollouts | Progressive delivery |
| external-dns | external-dns | external-dns | Automatic DNS records |
| reloader | reloader | reloader | Restart pods on ConfigMap/Secret changes |
| vpa | vertical-pod-autoscaler | kube-system | Vertical pod autoscaling |

Dev cluster also runs `bookinfo` (Istio demo app).

---

## Key Files

| File | Purpose |
|------|---------|
| `gke.tf` | GKE cluster definition (same for all workspaces) |
| `shared-network.tf` | VPC, subnets, Cloud NAT (created in gitops only) |
| `argocd.tf` | ArgoCD Helm release + cluster secrets |
| `eso.tf` | ESO GCP SA, Secret Manager secrets, CRDs, ClusterSecretStore, ExternalSecrets |
| `locals.tf` | Cluster maps, chart configs, template rendering |
| `variables.tf` | Variable definitions |
| `values.auto.tfvars` | Variable values (project ID, region, chart versions) |
| `templates/apps-values.yaml` | Helm values template for ArgoCD ApplicationSets |
| `templates/argocd-values.yaml` | Helm values for ArgoCD itself |
| `gke-applications/{cluster}/*.yaml` | Per-cluster application definitions |
| `cicd/cloudbuild.yaml` | Main apply pipeline |
| `cicd/cloudbuild-plan.yaml` | PR plan pipeline |
| `cicd/cloudbuild-destroy.yaml` | Nightly destroy pipeline |
| `cicd/cloudbuild-create.yaml` | Morning recreate pipeline |
