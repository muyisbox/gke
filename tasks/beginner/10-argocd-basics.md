# Task 10: ArgoCD Basics — Understanding the GitOps Control Plane

**Level:** Beginner

**Objective:** Access ArgoCD, understand how it manages applications, and see how the application YAML files in `gke-applications/` become running workloads.

## Prerequisites

Connect to the gitops cluster:
```bash
gcloud container clusters get-credentials gitops-cluster --zone us-central1-c --project cluster-dreams
```

## Part A: Access ArgoCD

1. Port-forward the ArgoCD server:
   ```bash
   kubectl port-forward svc/argo-cd-argocd-server -n argocd 8080:443
   ```

2. Get the admin password:
   ```bash
   kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo
   ```

3. Open `https://localhost:8080` in your browser. Log in as `admin`.

## Part B: Explore the UI

4. Answer these questions from the UI:
   - How many applications are managed?
   - How many clusters are registered? (Settings → Clusters)
   - Are all applications Healthy and Synced?
   - Find an application that is "OutOfSync" — what changed?

## Part C: Understand ApplicationSets

5. List the ApplicationSets:
   ```bash
   kubectl get applicationsets -n argocd
   ```

6. Describe one:
   ```bash
   kubectl describe applicationset dev-apps -n argocd
   ```

7. Open `templates/apps-values.yaml` and trace the flow:
   - The ApplicationSet uses a Git file generator
   - It reads YAML files from `gke-applications/{cluster}/*.yaml`
   - Each YAML file becomes one ArgoCD Application
   - ArgoCD deploys the Helm chart defined in each YAML to the target cluster

8. Open `gke-applications/dev/cert-manager.yaml` and map its fields to the ApplicationSet template:
   - `name` → Application name
   - `chart` → Helm chart to deploy
   - `repoURL` → Helm repository
   - `targetRevision` → Chart version
   - `namespace` → Target namespace on the cluster

## Part D: Verify CLI Access

9. List applications via kubectl:
   ```bash
   kubectl get applications -n argocd
   kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status
   ```

10. Check registered clusters:
    ```bash
    kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster -o custom-columns=NAME:.metadata.name
    ```

## Key Concepts

- **ArgoCD** runs on the gitops cluster and manages all 3 clusters
- **ApplicationSets** auto-generate Applications from YAML files in Git
- Adding a new YAML file to `gke-applications/dev/` automatically deploys a new app
- `selfHeal: true` means ArgoCD reverts manual changes
- `prune: true` means ArgoCD deletes resources removed from Git
