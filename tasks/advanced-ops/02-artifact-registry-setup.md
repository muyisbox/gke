# Task 2: Configure Google Artifact Registry with Workload Identity and ESO-Managed Credentials

**Level:** Advanced Operations

**Objective:** Set up Google Artifact Registry as a private container and Helm chart (OCI) registry. Configure Workload Identity for cluster-level pull access, then create long-lived credentials synced via ESO for CI/CD and ArgoCD.

## Context

This platform currently pulls all images from public registries. In production, you need:
1. A private Artifact Registry for your images and Helm charts
2. Workload Identity for pods that need to pull images (no keys stored in cluster)
3. Long-lived credentials in GCP Secret Manager for ArgoCD to pull OCI Helm charts
4. ESO to sync those credentials into Kubernetes secrets

## Steps

### Part A: Create the Artifact Registry

1. Create a Docker repository for container images:

   ```bash
   gcloud artifacts repositories create docker-images \
     --repository-format=docker \
     --location=us-central1 \
     --description="Container images for GKE platform" \
     --project=cluster-dreams
   ```

2. Create an OCI repository for Helm charts:

   ```bash
   gcloud artifacts repositories create helm-charts \
     --repository-format=docker \
     --location=us-central1 \
     --description="OCI Helm charts for GKE platform" \
     --project=cluster-dreams
   ```

   Note: Helm OCI charts use Docker-format repositories.

3. Verify both exist:

   ```bash
   gcloud artifacts repositories list --location=us-central1 --project=cluster-dreams
   ```

### Part B: Configure Workload Identity for Image Pulling

GKE nodes can use Workload Identity to pull images from Artifact Registry without storing keys. This is the recommended zero-trust approach.

4. Create a dedicated GCP service account for image pulling:

   ```bash
   gcloud iam service-accounts create artifact-reader \
     --display-name="Artifact Registry Reader - Workload Identity" \
     --project=cluster-dreams
   ```

5. Grant it read access to the registry:

   ```bash
   gcloud artifacts repositories add-iam-policy-binding docker-images \
     --location=us-central1 \
     --member="serviceAccount:artifact-reader@cluster-dreams.iam.gserviceaccount.com" \
     --role="roles/artifactregistry.reader" \
     --project=cluster-dreams

   gcloud artifacts repositories add-iam-policy-binding helm-charts \
     --location=us-central1 \
     --member="serviceAccount:artifact-reader@cluster-dreams.iam.gserviceaccount.com" \
     --role="roles/artifactregistry.reader" \
     --project=cluster-dreams
   ```

6. Grant GKE node service account pull access (this enables all pods on the node to pull):

   ```bash
   # Find the GKE node SA
   NODE_SA=$(gcloud container clusters describe dev-cluster \
     --zone=us-central1-c --project=cluster-dreams \
     --format='value(nodeConfig.serviceAccount)')

   gcloud artifacts repositories add-iam-policy-binding docker-images \
     --location=us-central1 \
     --member="serviceAccount:${NODE_SA}" \
     --role="roles/artifactregistry.reader" \
     --project=cluster-dreams
   ```

### Part C: Create Long-Lived Credentials for ArgoCD

ArgoCD's repo-server needs to pull OCI Helm charts from Artifact Registry. Since ArgoCD isn't running a GKE workload that can directly use node-level Workload Identity for Helm pulls, we need to create a service account key and store it in GCP Secret Manager.

7. Create a service account for ArgoCD Helm pulls:

   ```bash
   gcloud iam service-accounts create argocd-helm-puller \
     --display-name="ArgoCD Helm Chart Puller" \
     --project=cluster-dreams

   gcloud artifacts repositories add-iam-policy-binding helm-charts \
     --location=us-central1 \
     --member="serviceAccount:argocd-helm-puller@cluster-dreams.iam.gserviceaccount.com" \
     --role="roles/artifactregistry.reader" \
     --project=cluster-dreams
   ```

8. Create a key and store it in Secret Manager:

   ```bash
   # Create the key
   gcloud iam service-accounts keys create /tmp/argocd-helm-key.json \
     --iam-account=argocd-helm-puller@cluster-dreams.iam.gserviceaccount.com \
     --project=cluster-dreams

   # Store in Secret Manager
   gcloud secrets create argocd-artifact-registry-creds \
     --project=cluster-dreams \
     --replication-policy="automatic"

   # Create the secret data as a JSON with the fields ArgoCD expects
   cat <<EOF > /tmp/argocd-repo-secret.json
   {
     "username": "_json_key",
     "password": $(cat /tmp/argocd-helm-key.json | jq -Rs .),
     "registry": "us-central1-docker.pkg.dev"
   }
   EOF

   gcloud secrets versions add argocd-artifact-registry-creds \
     --data-file=/tmp/argocd-repo-secret.json \
     --project=cluster-dreams

   # Clean up local key files
   rm /tmp/argocd-helm-key.json /tmp/argocd-repo-secret.json
   ```

### Part D: Sync Credentials to Kubernetes via ESO

9. Create an ExternalSecret on the gitops cluster to sync the registry credentials into ArgoCD:

   ```yaml
   # artifact-registry-external-secret.yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: argocd-artifact-registry
     namespace: argocd
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: gcp-secret-manager
       kind: ClusterSecretStore
     target:
       name: argocd-artifact-registry-creds
       creationPolicy: Owner
       template:
         type: Opaque
         metadata:
           labels:
             argocd.argoproj.io/secret-type: repository
         data:
           type: helm
           name: artifact-registry
           enableOCI: "true"
           url: us-central1-docker.pkg.dev/cluster-dreams/helm-charts
           username: "{{ .username }}"
           password: "{{ .password }}"
     data:
     - secretKey: username
       remoteRef:
         key: argocd-artifact-registry-creds
         property: username
     - secretKey: password
       remoteRef:
         key: argocd-artifact-registry-creds
         property: password
   ```

   The `argocd.argoproj.io/secret-type: repository` label tells ArgoCD to treat this secret as a repository configuration.

10. Apply on the gitops cluster:

    ```bash
    kubectl apply -f artifact-registry-external-secret.yaml --context=gitops
    ```

11. Verify the secret was synced and ArgoCD recognizes the repository:

    ```bash
    kubectl get externalsecret argocd-artifact-registry -n argocd --context=gitops
    kubectl get secret argocd-artifact-registry-creds -n argocd --context=gitops -o yaml | grep -A2 labels
    ```

12. In the ArgoCD UI, go to Settings → Repositories. You should see `artifact-registry` listed.

### Part E: Configure imagePullSecrets for Private Images

13. For namespaces that need to pull private container images, create an ExternalSecret that syncs a `kubernetes.io/dockerconfigjson` secret:

    ```yaml
    # image-pull-external-secret.yaml
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: artifact-registry-pull
      namespace: default
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: gcp-secret-manager
        kind: ClusterSecretStore
      target:
        name: artifact-registry-pull-secret
        creationPolicy: Owner
        template:
          type: kubernetes.io/dockerconfigjson
          data:
            .dockerconfigjson: |
              {
                "auths": {
                  "us-central1-docker.pkg.dev": {
                    "username": "{{ .username }}",
                    "password": {{ .password | toJson }}
                  }
                }
              }
      data:
      - secretKey: username
        remoteRef:
          key: argocd-artifact-registry-creds
          property: username
      - secretKey: password
        remoteRef:
          key: argocd-artifact-registry-creds
          property: password
    ```

14. Apply and verify:

    ```bash
    kubectl apply -f image-pull-external-secret.yaml
    kubectl get secret artifact-registry-pull-secret -o jsonpath='{.type}'
    # Should output: kubernetes.io/dockerconfigjson
    ```

15. Use it in a deployment:

    ```yaml
    spec:
      imagePullSecrets:
      - name: artifact-registry-pull-secret
      containers:
      - name: app
        image: us-central1-docker.pkg.dev/cluster-dreams/docker-images/myapp:v1
    ```

### Part F: Terraform Integration

16. In production, the Artifact Registry and IAM bindings should be managed by Terraform. Add to `eso.tf` (or a new `artifact-registry.tf`):

    ```hcl
    resource "google_artifact_registry_repository" "docker_images" {
      count         = terraform.workspace == "gitops" ? 1 : 0
      location      = var.region
      repository_id = "docker-images"
      format        = "DOCKER"
      description   = "Container images for GKE platform"
    }

    resource "google_artifact_registry_repository" "helm_charts" {
      count         = terraform.workspace == "gitops" ? 1 : 0
      location      = var.region
      repository_id = "helm-charts"
      format        = "DOCKER"
      description   = "OCI Helm charts for GKE platform"
    }

    resource "google_service_account" "artifact_reader" {
      count        = terraform.workspace == "gitops" ? 1 : 0
      account_id   = "artifact-reader"
      display_name = "Artifact Registry Reader - Workload Identity"
      project      = var.project_id
    }

    resource "google_artifact_registry_repository_iam_member" "reader" {
      count      = terraform.workspace == "gitops" ? 1 : 0
      project    = var.project_id
      location   = var.region
      repository = google_artifact_registry_repository.docker_images[0].name
      role       = "roles/artifactregistry.reader"
      member     = "serviceAccount:${google_service_account.artifact_reader[0].email}"
    }
    ```

### Part G: Verify End-to-End

17. Test pulling a public image, tagging it, and pushing to your registry:

    ```bash
    # Authenticate Docker to Artifact Registry
    gcloud auth configure-docker us-central1-docker.pkg.dev

    # Pull, tag, push
    docker pull nginx:1.25
    docker tag nginx:1.25 us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
    docker push us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
    ```

18. Deploy using the private image:

    ```bash
    kubectl run test-private --image=us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
    kubectl get pod test-private
    kubectl delete pod test-private
    ```

## Key Concepts

- **Workload Identity (node-level)**: GKE nodes authenticate to GCP APIs natively — no keys needed for image pulls
- **Service account keys**: Only needed when a component can't use Workload Identity directly (e.g., ArgoCD OCI pulls)
- **ESO for credentials**: Syncs keys from GCP Secret Manager → K8s secrets, with auto-refresh
- **ArgoCD repository secrets**: Label `argocd.argoproj.io/secret-type: repository` auto-registers repos
- **OCI Helm charts**: Use Docker-format repositories; ArgoCD supports them with `enableOCI: true`
- **imagePullSecrets**: Per-namespace; can be auto-created with ESO ExternalSecrets
- **Credential rotation**: Update the GCP Secret Manager version → ESO syncs → ArgoCD/pods pick up new creds

## Cleanup

```bash
kubectl delete -f artifact-registry-external-secret.yaml --context=gitops
kubectl delete -f image-pull-external-secret.yaml
gcloud secrets delete argocd-artifact-registry-creds --project=cluster-dreams --quiet
gcloud iam service-accounts delete argocd-helm-puller@cluster-dreams.iam.gserviceaccount.com --project=cluster-dreams --quiet
gcloud iam service-accounts delete artifact-reader@cluster-dreams.iam.gserviceaccount.com --project=cluster-dreams --quiet
gcloud artifacts repositories delete docker-images --location=us-central1 --project=cluster-dreams --quiet
gcloud artifacts repositories delete helm-charts --location=us-central1 --project=cluster-dreams --quiet
```
