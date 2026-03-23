# Task 6: Configure Docker Hub as a Remote Registry via Artifact Registry

**Level:** Advanced Operations

**Objective:** Set up Google Artifact Registry as a pull-through cache for Docker Hub using remote repositories. Configure ESO to manage Docker Hub credentials, and set up Kyverno to rewrite image references to use the proxy.

## Context

Direct pulls from Docker Hub are subject to rate limits (100 pulls/6 hours for anonymous, 200 for free accounts). Artifact Registry can act as a pull-through cache, providing:
- No rate limit issues (cached images are served locally)
- Vulnerability scanning on cached images
- Audit trail of all images used
- Single credential management point

## Steps

### Part A: Create a Remote Repository in Artifact Registry

1. Store Docker Hub credentials in GCP Secret Manager:

   ```bash
   # Create a secret with Docker Hub credentials
   echo -n '{"username":"your-dockerhub-username","password":"your-dockerhub-token"}' | \
     gcloud secrets create dockerhub-credentials \
       --data-file=- \
       --project=cluster-dreams \
       --replication-policy="automatic"
   ```

   Use a Docker Hub access token (not your password) from https://hub.docker.com/settings/security.

2. Create the remote repository that proxies Docker Hub:

   ```bash
   gcloud artifacts repositories create dockerhub-proxy \
     --repository-format=docker \
     --location=us-central1 \
     --description="Docker Hub pull-through cache" \
     --mode=remote-repository \
     --remote-repo-config-desc="Docker Hub proxy" \
     --remote-docker-repo=DOCKER-HUB \
     --remote-username=your-dockerhub-username \
     --remote-password-secret-version=projects/cluster-dreams/secrets/dockerhub-credentials/versions/latest \
     --project=cluster-dreams
   ```

3. Verify the repository:

   ```bash
   gcloud artifacts repositories describe dockerhub-proxy \
     --location=us-central1 --project=cluster-dreams
   ```

### Part B: Configure GKE to Pull Through the Proxy

4. Pull an image through the proxy to verify it works:

   ```bash
   # Authenticate Docker
   gcloud auth configure-docker us-central1-docker.pkg.dev

   # Pull nginx through the proxy
   docker pull us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy/library/nginx:1.25
   ```

5. Verify the image is cached:

   ```bash
   gcloud artifacts docker images list \
     us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy \
     --include-tags --project=cluster-dreams
   ```

### Part C: Sync Docker Hub Credentials via ESO

6. Create an ExternalSecret that provides imagePullSecrets for namespaces that need Docker Hub access:

   ```yaml
   # dockerhub-pull-secret.yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: dockerhub-pull-credentials
     namespace: default
   spec:
     refreshInterval: 24h
     secretStoreRef:
       name: gcp-secret-manager
       kind: ClusterSecretStore
     target:
       name: dockerhub-pull-secret
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
         key: dockerhub-credentials
         property: username
     - secretKey: password
       remoteRef:
         key: dockerhub-credentials
         property: password
   ```

7. Apply and verify:

   ```bash
   kubectl apply -f dockerhub-pull-secret.yaml
   kubectl get secret dockerhub-pull-secret -o jsonpath='{.type}'
   # Should output: kubernetes.io/dockerconfigjson
   ```

### Part D: Kyverno Policy to Rewrite Image References

8. Create a Kyverno mutation policy that rewrites Docker Hub image references to use the Artifact Registry proxy:

   ```yaml
   # policies/rewrite-dockerhub-images.yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: rewrite-dockerhub-to-proxy
     annotations:
       policies.kyverno.io/title: Rewrite Docker Hub Images to Artifact Registry Proxy
       policies.kyverno.io/category: Supply Chain Security
       policies.kyverno.io/description: >-
         Rewrites Docker Hub image references to use the
         Artifact Registry pull-through cache to avoid
         Docker Hub rate limits and enable vulnerability scanning.
   spec:
     rules:
     - name: rewrite-docker-io
       match:
         any:
         - resources:
             kinds:
             - Pod
       exclude:
         any:
         - resources:
             namespaces:
             - kube-system
             - kyverno
       mutate:
         foreach:
         - list: "request.object.spec.containers"
           patchStrategicMerge:
             spec:
               containers:
               - name: "{{ element.name }}"
                 image: "{{ regex_replace_all('docker\\.io/(.+)', element.image, 'us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy/$1') }}"
     - name: rewrite-library-images
       match:
         any:
         - resources:
             kinds:
             - Pod
       exclude:
         any:
         - resources:
             namespaces:
             - kube-system
             - kyverno
       mutate:
         foreach:
         - list: "request.object.spec.containers"
           preconditions:
             all:
             - key: "{{ element.image }}"
               operator: NotEquals
               value: ""
             - key: "{{ contains(element.image, '/') }}"
               operator: Equals
               value: false
             - key: "{{ contains(element.image, '.') }}"
               operator: Equals
               value: false
           patchStrategicMerge:
             spec:
               containers:
               - name: "{{ element.name }}"
                 image: "us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy/library/{{ element.image }}"
   ```

   This policy handles:
   - `docker.io/library/nginx:1.25` → `us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy/library/nginx:1.25`
   - `nginx:1.25` (no registry prefix) → `us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy/library/nginx:1.25`

9. Apply and test:

   ```bash
   kubectl apply -f policies/rewrite-dockerhub-images.yaml

   # Check the mutation
   kubectl run test-rewrite --image=nginx:1.25 -n default --dry-run=server -o yaml | grep image:
   # Should show: us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy/library/nginx:1.25
   ```

### Part E: Kyverno Generate — Auto-Create imagePullSecrets

10. Auto-inject imagePullSecrets into every service account in new namespaces:

    ```yaml
    # policies/generate-pull-secrets.yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: generate-image-pull-secrets
      annotations:
        policies.kyverno.io/title: Generate Image Pull Secrets
        policies.kyverno.io/category: Supply Chain Security
    spec:
      rules:
      - name: copy-pull-secret
        match:
          any:
          - resources:
              kinds:
              - Namespace
        exclude:
          any:
          - resources:
              names:
              - kube-system
              - kyverno
        generate:
          apiVersion: v1
          kind: Secret
          name: registry-pull-secret
          namespace: "{{request.object.metadata.name}}"
          synchronize: true
          clone:
            namespace: default
            name: dockerhub-pull-secret
      - name: patch-default-sa
        match:
          any:
          - resources:
              kinds:
              - ServiceAccount
              names:
              - default
        exclude:
          any:
          - resources:
              namespaces:
              - kube-system
              - kyverno
        mutate:
          patchStrategicMerge:
            imagePullSecrets:
            - name: registry-pull-secret
    ```

11. Test:

    ```bash
    kubectl apply -f policies/generate-pull-secrets.yaml
    kubectl create namespace pull-test
    kubectl get secret registry-pull-secret -n pull-test  # Should exist (cloned)
    kubectl get sa default -n pull-test -o yaml | grep imagePullSecrets  # Should have it
    kubectl delete namespace pull-test
    ```

### Part F: Enable Vulnerability Scanning on Cached Images

12. Enable vulnerability scanning on the Artifact Registry:

    ```bash
    gcloud services enable containerscanning.googleapis.com --project=cluster-dreams
    ```

13. After pulling images through the proxy, check for vulnerabilities:

    ```bash
    gcloud artifacts docker images list \
      us-central1-docker.pkg.dev/cluster-dreams/dockerhub-proxy \
      --show-occurrences --project=cluster-dreams
    ```

## Architecture

```
Developer writes: image: nginx:1.25
    ↓
Kyverno mutates to: us-central1-docker.pkg.dev/.../dockerhub-proxy/library/nginx:1.25
    ↓
GKE node pulls from Artifact Registry proxy
    ↓
Artifact Registry checks cache:
  - Cached? → Serve from cache (no Docker Hub call)
  - Not cached? → Pull from Docker Hub, cache, then serve
    ↓
Container Scanning API scans cached image
    ↓
Pod runs with proxied, scanned image
```

## Key Concepts

- **Remote repository**: Artifact Registry acts as a transparent proxy for Docker Hub
- **Rate limit avoidance**: Cached images don't count against Docker Hub limits
- **Vulnerability scanning**: GCP Container Analysis scans every cached image
- **Image rewriting**: Kyverno transparently redirects pulls without app changes
- **Credential management**: ESO syncs Docker Hub credentials from Secret Manager
- **imagePullSecret propagation**: Generate policies ensure every namespace gets pull creds

## Cleanup

```bash
kubectl delete clusterpolicy rewrite-dockerhub-to-proxy generate-image-pull-secrets
kubectl delete externalsecret dockerhub-pull-credentials -n default
gcloud artifacts repositories delete dockerhub-proxy --location=us-central1 --project=cluster-dreams --quiet
gcloud secrets delete dockerhub-credentials --project=cluster-dreams --quiet
```
