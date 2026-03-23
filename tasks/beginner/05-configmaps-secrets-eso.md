# Task 5: ConfigMaps, Secrets, and External Secrets Operator

**Level:** Beginner

**Objective:** Understand how configuration and secrets are managed, including the External Secrets Operator that syncs secrets from GCP Secret Manager.

## Part A: ConfigMaps

1. List ConfigMaps in `istio-system`:
   ```bash
   kubectl get configmaps -n istio-system
   ```

2. View the Istio mesh configuration:
   ```bash
   kubectl get configmap istio -n istio-system -o yaml
   ```
   What is the mesh's trust domain? What is the default proxy concurrency?

## Part B: Kubernetes Secrets

3. List secrets in the `cert-manager` namespace:
   ```bash
   kubectl get secrets -n cert-manager
   ```

4. What types of secrets exist? (Hint: look at the TYPE column)
   ```bash
   kubectl get secrets -n cert-manager -o custom-columns=NAME:.metadata.name,TYPE:.type
   ```

5. Describe a `kubernetes.io/tls` secret (do NOT decode it):
   ```bash
   kubectl describe secret <tls-secret-name> -n cert-manager
   ```

## Part C: External Secrets Operator

6. Open `gke-applications/dev/external-secrets.yaml`. Answer:
   - What version of ESO is deployed?
   - How many replicas?
   - What GCP service account is used for Workload Identity?

7. Check if ESO is running:
   ```bash
   kubectl get pods -n external-secrets
   ```

8. List any ExternalSecret and ClusterSecretStore resources:
   ```bash
   kubectl get externalsecrets -A
   kubectl get clustersecretstores -A
   ```

9. Now switch to the gitops cluster and see how ESO is configured at the infrastructure level:
   ```bash
   gcloud container clusters get-credentials gitops-cluster --zone us-central1-c --project cluster-dreams
   kubectl get externalsecrets -n argocd
   kubectl get clustersecretstores
   ```

10. Open `eso.tf` and trace the flow:
    - GCP Secret Manager stores cluster endpoint + CA cert
    - ClusterSecretStore connects ESO to GCP Secret Manager
    - ExternalSecret pulls the secret and creates a Kubernetes secret in the `argocd` namespace
    - ArgoCD uses this secret to connect to remote clusters

## Key Concepts

- **ConfigMaps**: Non-sensitive configuration data
- **Secrets**: Sensitive data (tokens, certs, passwords) — base64 encoded, NOT encrypted at rest by default
- **ESO**: Syncs secrets from external providers (GCP Secret Manager) into Kubernetes secrets
- **Workload Identity**: Allows pods to authenticate to GCP without service account keys
