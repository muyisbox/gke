# Task 10: Multi-Cluster Operations and Context Management

**Level:** Intermediate

**Objective:** Work across all three clusters simultaneously, compare configurations, and understand the hub-spoke model.

## Steps

### Part A: Connect to All Clusters

1. Get credentials for all three clusters:

   ```bash
   gcloud container clusters get-credentials dev-cluster --zone us-central1-c --project cluster-dreams
   gcloud container clusters get-credentials staging-cluster --zone us-central1-c --project cluster-dreams
   gcloud container clusters get-credentials gitops-cluster --zone us-central1-c --project cluster-dreams
   ```

2. List all contexts and rename them for convenience:

   ```bash
   kubectl config get-contexts
   kubectl config rename-context gke_cluster-dreams_us-central1-c_dev-cluster dev
   kubectl config rename-context gke_cluster-dreams_us-central1-c_staging-cluster staging
   kubectl config rename-context gke_cluster-dreams_us-central1-c_gitops-cluster gitops
   ```

### Part B: Compare Clusters

3. Compare node counts across clusters:

   ```bash
   echo "=== DEV ===" && kubectl get nodes --context=dev --no-headers | wc -l
   echo "=== STAGING ===" && kubectl get nodes --context=staging --no-headers | wc -l
   echo "=== GITOPS ===" && kubectl get nodes --context=gitops --no-headers | wc -l
   ```

4. Compare namespaces:

   ```bash
   diff <(kubectl get ns --context=dev -o name | sort) <(kubectl get ns --context=staging -o name | sort)
   ```

   What's different between dev and staging? (Hint: bookinfo namespace)

5. Compare Istio versions across clusters:

   ```bash
   for ctx in dev staging gitops; do
     echo "=== $ctx ==="
     kubectl get pods -n istio-system --context=$ctx -l app=istiod -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null
     echo
   done
   ```

### Part C: Understand the Hub-Spoke Model

6. On the gitops cluster, list what ArgoCD manages:

   ```bash
   kubectl get applications -n argocd --context=gitops -o custom-columns=NAME:.metadata.name,CLUSTER:.spec.destination.name,HEALTH:.status.health.status,SYNC:.status.sync.status
   ```

7. List the registered clusters:

   ```bash
   kubectl get secrets -n argocd --context=gitops -l argocd.argoproj.io/secret-type=cluster -o custom-columns=NAME:.metadata.name
   ```

8. Check how ArgoCD connects to remote clusters — look at the ESO-managed secrets:

   ```bash
   kubectl get externalsecrets -n argocd --context=gitops
   ```

### Part D: Cross-Cluster Troubleshooting

9. Verify the same app is healthy across all clusters:

   ```bash
   for ctx in dev staging gitops; do
     echo "=== $ctx: cert-manager ==="
     kubectl get pods -n cert-manager --context=$ctx
   done
   ```

10. Check if any cluster has pods in a bad state:

    ```bash
    for ctx in dev staging gitops; do
      echo "=== $ctx ==="
      kubectl get pods -A --context=$ctx --field-selector 'status.phase!=Running,status.phase!=Succeeded' 2>/dev/null
    done
    ```

### Part E: Understand the Nightly Destroy/Recreate

11. Open `cicd/cloudbuild-destroy.yaml` and `cicd/cloudbuild-create.yaml`:
    - What time does destroy run? (2 AM EST)
    - What time does create run? (10 AM EST)
    - Which clusters are destroyed? (dev and staging — NOT gitops)

12. Why does gitops stay up 24/7?
    - It runs ArgoCD (the control plane)
    - It holds the shared network (VPC, router, NAT)
    - It manages ESO secrets for cluster reconnection

13. When dev/staging are recreated, how does ArgoCD reconnect?
    - Terraform updates GCP Secret Manager with new cluster endpoint/CA
    - ESO refreshes the K8s secret (1-hour interval)
    - ArgoCD detects the new cluster and re-deploys all apps

## Key Concepts

- **Hub-spoke**: gitops cluster is the hub, dev/staging are spokes
- **Context switching**: Use `--context=` flag to avoid switching contexts
- **Rename contexts**: Makes multi-cluster work much easier
- **ArgoCD manages all clusters** from a single control plane
- **Nightly destroy** saves ~67% on dev/staging compute costs
