# Task 7: Deployments, ReplicaSets, and ArgoCD Self-Healing

**Level:** Beginner

**Objective:** Understand the deployment hierarchy and see how ArgoCD enforces desired state through GitOps.

## Part A: Deployment Hierarchy

1. List all deployments in `cert-manager`:
   ```bash
   kubectl get deployments -n cert-manager
   ```

2. Check the cert-manager deployment's desired vs current replicas:
   ```bash
   kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.spec.replicas}'
   ```
   Compare this to `gke-applications/dev/cert-manager.yaml` — the `replicaCount` value.

3. View the ReplicaSets behind the deployment:
   ```bash
   kubectl get replicasets -n cert-manager
   ```
   Why might there be more than one ReplicaSet?

## Part B: Manual Scaling vs GitOps

4. Scale cert-manager to 3 replicas manually:
   ```bash
   kubectl scale deployment cert-manager -n cert-manager --replicas=3
   kubectl get pods -n cert-manager -w
   ```

5. Wait 1-2 minutes and check again:
   ```bash
   kubectl get deployment cert-manager -n cert-manager
   ```
   ArgoCD's sync policy has `selfHeal: true` — it will detect the drift and revert to 2 replicas.

6. Verify in ArgoCD (from gitops cluster):
   ```bash
   gcloud container clusters get-credentials gitops-cluster --zone us-central1-c --project cluster-dreams
   kubectl get applications -n argocd | grep cert-manager
   ```

7. Switch back to dev:
   ```bash
   gcloud container clusters get-credentials dev-cluster --zone us-central1-c --project cluster-dreams
   ```

## Part C: Understanding Why This Matters

8. Open `templates/apps-values.yaml` and find the sync policy:
   - Is `automated` sync enabled?
   - Is `prune` enabled? What does this do?
   - Is `selfHeal` enabled? What does this do?

9. What is the `CreateNamespace=true` sync option for?

## Key Concepts

- **Deployment** → owns **ReplicaSet** → owns **Pods** (3-layer hierarchy)
- **ArgoCD self-heal**: Automatically reverts manual cluster changes to match Git
- **ArgoCD prune**: Deletes resources that no longer exist in Git
- In GitOps, the Git repo is the single source of truth — manual kubectl changes are temporary
