# Onboarding a New Application

Applications are deployed via ArgoCD ApplicationSets using a Git file generator. To add a new app, you create a single YAML file in the appropriate cluster directory. No Terraform changes are required.

---

## How It Works

```
gke-applications/
├── dev/
│   └── my-app.yaml       ← you create this file
├── staging/
│   └── my-app.yaml
└── gitops/
    └── my-app.yaml       (if also needed on the hub cluster)
```

ArgoCD's `{cluster}-apps` ApplicationSet watches `gke-applications/{cluster}/*.yaml` on the `master` branch. When you push a new YAML file, ArgoCD automatically creates an Application and begins deploying the Helm chart.

---

## Application File Format

Every application file must have these required fields:

```yaml
name: my-app                               # Unique within the cluster; becomes the Helm release name
chart: my-chart-name                       # Helm chart name in the repo
repoURL: https://charts.example.com        # Helm chart repository URL
targetRevision: "1.2.3"                   # Chart version (pin to exact version in prod)
namespace: my-namespace                    # Target namespace (created automatically)
cluster_env: dev                           # Label only — use dev, staging, or gitops
```

### With Helm Values

```yaml
name: my-app
chart: my-chart-name
repoURL: https://charts.example.com
targetRevision: "1.2.3"
namespace: my-namespace
cluster_env: dev
helm:
  values:
    replicaCount: 2
    image:
      tag: "v1.0.0"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi
```

### With Helm Values Files

```yaml
name: my-app
chart: my-chart-name
repoURL: https://charts.example.com
targetRevision: "1.2.3"
namespace: my-namespace
cluster_env: dev
helm:
  valueFiles:
    - values.yaml
    - values-dev.yaml
```

Note: `valueFiles` paths are relative to the chart root in the Helm repository.

---

## Step-by-Step: Add an App to Dev and Staging

### 1. Create the application file

```bash
# Create for dev
cat > gke-applications/dev/my-app.yaml << 'EOF'
name: my-app
chart: my-chart
repoURL: https://charts.example.com
targetRevision: "1.0.0"
namespace: my-app
cluster_env: dev
helm:
  values:
    replicaCount: 1
    serviceMonitor:
      enabled: true
      labels:
        release: prometheus-monitoring
EOF

# Copy and adjust for staging
cp gke-applications/dev/my-app.yaml gke-applications/staging/my-app.yaml
sed -i '' 's/cluster_env: dev/cluster_env: staging/' gke-applications/staging/my-app.yaml
# Update replica count or any staging-specific values
```

### 2. Commit and push

```bash
git add gke-applications/
git commit -m "Add my-app to dev and staging clusters"
git push origin master
```

### 3. Verify in ArgoCD

```bash
# Connect to gitops cluster
gcloud container clusters get-credentials gitops-cluster \
  --region us-central1 --project cluster-dreams

# Watch for the new Application objects to appear
kubectl get applications -n argocd | grep my-app

# Check sync status
kubectl describe application my-app-dev -n argocd
kubectl describe application my-app-staging -n argocd
```

Or use the ArgoCD UI (port-forward to access it):

```bash
kubectl port-forward svc/argo-cd-argocd-server 8080:443 -n argocd
# Open https://localhost:8080
```

---

## Real-World Examples

### cert-manager (minimal config)

```yaml
name: cert-manager
chart: cert-manager
repoURL: https://charts.jetstack.io
targetRevision: "1.20.0"
namespace: cert-manager
cluster_env: dev
helm:
  values:
    crds:
      enabled: true
    replicaCount: 2
    prometheus:
      enabled: true
      servicemonitor:
        enabled: true
        labels:
          release: prometheus-monitoring
```

### External Secrets Operator (with Workload Identity annotation)

```yaml
name: external-secrets
chart: external-secrets
repoURL: https://charts.external-secrets.io
targetRevision: "2.1.0"
namespace: external-secrets
cluster_env: dev
helm:
  values:
    crds:
      install: true
    replicaCount: 2
    serviceAccount:
      create: true
      annotations:
        iam.gke.io/gcp-service-account: eso-controller@cluster-dreams.iam.gserviceaccount.com
    serviceMonitor:
      enabled: true
      labels:
        release: prometheus-monitoring
```

### Loki (SingleBinary mode for filesystem storage)

```yaml
name: loki-stack
chart: loki
repoURL: https://grafana.github.io/helm-charts
targetRevision: "6.30.1"
namespace: logging
cluster_env: dev
helm:
  values:
    deploymentMode: SingleBinary
    loki:
      auth_enabled: false
      storage:
        type: filesystem
    singleBinary:
      replicas: 1
    read:
      replicas: 0
    write:
      replicas: 0
    backend:
      replicas: 0
```

---

## Naming Conventions

| Field | Convention | Example |
|-------|-----------|---------|
| `name` | kebab-case, descriptive | `cert-manager`, `prometheus-monitoring` |
| `namespace` | matches app name or team domain | `cert-manager`, `monitoring`, `logging` |
| `cluster_env` | must match the directory name | `dev`, `staging`, `gitops` |
| File name | same as `name` field | `cert-manager.yaml` |

---

## Handling Namespace-Sensitive Apps

Some apps should never run in `kube-system`. The platform does not use `managedNamespaceMetadata`, so namespaces are created clean without any Istio labels. If your app needs to disable sidecar injection in its namespace, add an annotation at the app level:

```yaml
helm:
  values:
    podAnnotations:
      sidecar.istio.io/inject: "false"
```

Or for cluster-wide resources (webhooks, operators) that conflict with Istio, annotate the namespace separately using a raw Kubernetes manifest approach (create a separate app with `chart: raw` or use an init job).

---

## Updating an Existing App

To change an app's chart version or values:

1. Edit the YAML file in the relevant `gke-applications/{cluster}/` directory.
2. Commit and push.
3. ArgoCD detects the change within the poll interval (default: 3 minutes) and updates the Application.
4. Because `selfHeal: true` and `prune: true` are set, ArgoCD will automatically sync.

To pin a specific Git revision for the ApplicationSet (instead of `master`), change the `revision` field in `templates/apps-values.yaml` and re-apply via Terraform.

---

## Removing an App

1. Delete the YAML file from `gke-applications/{cluster}/`.
2. Commit and push.
3. ArgoCD detects the file is gone, deletes the Application, and prunes all resources it deployed (because `prune: true` is set in the sync policy).

```bash
git rm gke-applications/dev/my-app.yaml
git commit -m "Remove my-app from dev cluster"
git push origin master
```

---

## Troubleshooting

### App stuck in Unknown state

Check if the required fields are present:

```bash
kubectl describe application my-app-dev -n argocd | grep -A5 "Status:"
```

Common causes:
- Missing `repoURL` or `chart` — always required
- `helm.values` present but `templatePatch` not applying — check that the YAML is valid (no tabs, proper indentation)

### App OutOfSync but not auto-syncing

ArgoCD may have hit an error during sync. Check:

```bash
kubectl describe application my-app-dev -n argocd | grep -A20 "Conditions:"
```

Common causes:
- Chart version doesn't exist in the repo
- Helm values reference a key that doesn't exist in the chart's `values.yaml`
- Resource already exists in the cluster with a different owner (use `ServerSideApply=true` sync option, already enabled by default)

### Namespace not created

`CreateNamespace=true` is set in the default sync policy. If the namespace isn't being created, the app is likely in an error state before the namespace creation step. Check the application events.
