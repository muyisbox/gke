# Task 10: Disaster Recovery — Cluster Recreation and State Recovery

**Level:** Advanced

**Objective:** Understand and practice the complete disaster recovery workflow, including what happens during the nightly destroy/recreate cycle and how to recover from state corruption.

## Context

This platform destroys dev and staging clusters nightly at 2 AM EST and recreates them at 10 AM EST (see `cicd/cloudbuild-destroy.yaml` and `cicd/cloudbuild-create.yaml`). The gitops cluster runs 24/7 because it holds ArgoCD and the shared network.

## Steps

### Part A: Understand the Destroy/Recreate Flow

1. Open `cicd/cloudbuild-destroy.yaml`:
   - What workspaces are destroyed?
   - What Terraform command is used? (`terraform destroy -auto-approve`)
   - What's the timeout?

2. Open `cicd/cloudbuild-create.yaml`:
   - What's the apply order? (gitops first, then dev/staging)
   - Why does gitops need to be applied first?

3. Trace the ArgoCD reconnection flow after a cluster is recreated:

   ```
   Terraform apply (dev workspace)
     → Creates new GKE cluster with new endpoint + CA cert
     → Updates GCP Secret Manager with new credentials (eso.tf)

   ESO on gitops cluster
     → Detects secret change (1-hour refresh interval)
     → Updates K8s secret in argocd namespace

   ArgoCD
     → Detects cluster credential change
     → Reconnects to new dev-cluster
     → Syncs all apps from gke-applications/dev/
   ```

### Part B: Simulate Cluster Unavailability

4. On the gitops cluster, check ArgoCD's current view:

   ```bash
   kubectl get applications -n argocd --context=gitops -o custom-columns=NAME:.metadata.name,CLUSTER:.spec.destination.name,HEALTH:.status.health.status
   ```

5. Check the cluster secrets:

   ```bash
   kubectl get secrets -n argocd --context=gitops -l argocd.argoproj.io/secret-type=cluster
   ```

6. Describe a cluster secret to see the stored endpoint:

   ```bash
   kubectl get secret dev-cluster-secret -n argocd --context=gitops -o jsonpath='{.data.server}' | base64 -d && echo
   ```

7. Check the ExternalSecret that keeps this updated:

   ```bash
   kubectl get externalsecret -n argocd --context=gitops
   kubectl describe externalsecret dev-cluster-secret -n argocd --context=gitops
   ```

### Part C: Terraform State Investigation

8. List workspaces and their state files:

   ```bash
   terraform workspace list
   gsutil ls gs://cluster-dreams-terraform/terraform/state/
   ```

9. Check the current state for dev:

   ```bash
   terraform workspace select dev
   terraform state list | head -20
   terraform state show module.gke.google_container_cluster.primary
   ```

10. Key resources in the state:
    - `module.gke.google_container_cluster.primary` — The cluster itself
    - `module.gke.google_container_node_pool.pools["node-pool-01"]` — The node pool
    - `module.shared-network[0]` — Only in gitops state

### Part D: Terraform State Recovery Scenarios

11. **Scenario: State drift** — Someone modified the cluster via `gcloud` instead of Terraform:

    ```bash
    # Detect drift
    terraform plan
    # If the plan shows unexpected changes, investigate before applying
    ```

12. **Scenario: Orphaned resources** — Terraform state was deleted but resources still exist:

    ```bash
    # Import existing resources back into state
    terraform import 'module.gke.google_container_cluster.primary' 'projects/cluster-dreams/locations/us-central1/clusters/dev-cluster'
    ```

13. **Scenario: State lock stuck** — A previous apply crashed and left the state locked:

    ```bash
    # Check for lock
    terraform plan
    # If locked, force unlock (use with caution):
    terraform force-unlock <LOCK_ID>
    ```

### Part E: What If the Gitops Cluster Goes Down?

14. This is the most critical failure scenario. If gitops cluster is lost:
    - ArgoCD is gone — no automated deployments
    - ESO control plane is gone — no secret syncing
    - Shared network is still there (it's a GCP resource, not in the cluster)

15. Recovery steps:
    1. `terraform workspace select gitops && terraform apply` — Recreates the gitops cluster
    2. ArgoCD Helm chart deploys automatically (it's in the Terraform)
    3. ESO CRDs and ClusterSecretStore are recreated by Terraform
    4. ApplicationSets redeploy all apps to all clusters
    5. Total recovery time: ~15-20 minutes

16. Check `moved.tf` — state migration blocks prevent resource recreation during Terraform refactoring:

    ```bash
    cat moved.tf
    ```

### Part F: Backup and Recovery Best Practices

17. Discussion questions:
    - Why is the Terraform state stored in GCS instead of locally?
    - What would happen if the GCS state bucket was deleted?
    - How could you reduce the 1-hour ESO refresh interval for faster cluster reconnection?
    - Should you backup ArgoCD's application state? Why or why not? (Answer: No — Git is the backup)
    - What's the blast radius if someone runs `terraform destroy` on the gitops workspace?

18. Verify your state is backed up:

    ```bash
    gsutil ls -l gs://cluster-dreams-terraform/terraform/state/
    ```

## Key Concepts

- **Gitops cluster is the single point of failure** — it must be the most protected
- **Terraform state is critical** — losing it means losing track of what's deployed
- **ArgoCD makes recovery fast** — all app definitions are in Git, not in the cluster
- **ESO refresh interval** controls how fast ArgoCD reconnects to recreated clusters
- **Nightly destroy** works because everything is defined in code — nothing is manual
- **moved blocks** prevent state corruption during Terraform refactoring

## Emergency Recovery Cheatsheet

```bash
# 1. Check what exists
gcloud container clusters list --project=cluster-dreams

# 2. Verify Terraform state matches reality
terraform workspace select <env>
terraform plan

# 3. If state is lost, import resources
terraform import 'module.gke.google_container_cluster.primary' 'projects/cluster-dreams/locations/us-central1/clusters/<env>-cluster'

# 4. If cluster is gone, recreate
terraform apply

# 5. Force ArgoCD to resync all apps
kubectl patch application <app> -n argocd --type='merge' -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```
