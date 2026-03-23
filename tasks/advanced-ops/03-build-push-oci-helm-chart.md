# Task 3: Build, Package, and Push a Helm Chart as OCI to Artifact Registry

**Level:** Advanced Operations

**Objective:** Create a custom Helm chart from scratch, package it as an OCI artifact, push it to Google Artifact Registry, register the repository in ArgoCD, and deploy it to the dev cluster via the GitOps pipeline.

## Prerequisites

- Google Artifact Registry repositories created (Task 2)
- ArgoCD repository credentials synced via ESO (Task 2)
- Helm 3.8+ installed (OCI support)

## Steps

### Part A: Create the Helm Chart

1. Create a chart for a platform API service:

   ```bash
   mkdir -p /tmp/helm-charts
   cd /tmp/helm-charts
   helm create platform-api
   ```

2. Clean up the generated boilerplate. Replace `platform-api/Chart.yaml`:

   ```yaml
   apiVersion: v2
   name: platform-api
   description: Internal platform API service for the GKE platform
   type: application
   version: 0.1.0
   appVersion: "1.0.0"
   maintainers:
   - name: platform-team
     email: platform@example.com
   keywords:
   - api
   - platform
   - internal
   ```

3. Replace `platform-api/values.yaml` with production-ready defaults:

   ```yaml
   replicaCount: 2

   image:
     repository: us-central1-docker.pkg.dev/cluster-dreams/docker-images/platform-api
     pullPolicy: IfNotPresent
     tag: "1.0.0"

   imagePullSecrets: []

   serviceAccount:
     create: true
     annotations: {}
     name: ""

   podAnnotations:
     sidecar.istio.io/inject: "true"

   podLabels:
     app.kubernetes.io/name: platform-api
     team: platform

   service:
     type: ClusterIP
     port: 80
     targetPort: 8080
     name: http

   resources:
     requests:
       cpu: 100m
       memory: 128Mi
     limits:
       memory: 256Mi

   autoscaling:
     enabled: true
     minReplicas: 2
     maxReplicas: 10
     targetCPUUtilizationPercentage: 70
     targetMemoryUtilizationPercentage: 80

   livenessProbe:
     httpGet:
       path: /healthz
       port: http
     initialDelaySeconds: 15
     periodSeconds: 10

   readinessProbe:
     httpGet:
       path: /ready
       port: http
     initialDelaySeconds: 5
     periodSeconds: 5

   env: []

   envFrom: []

   configMap:
     enabled: false
     data: {}

   secrets:
     enabled: false
     externalSecret:
       enabled: false
       secretStoreRef:
         name: gcp-secret-manager
         kind: ClusterSecretStore
       refreshInterval: 5m
       remoteRef:
         key: ""
   ```

4. Replace `platform-api/templates/deployment.yaml`:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: {{ include "platform-api.fullname" . }}
     labels:
       {{- include "platform-api.labels" . | nindent 4 }}
   spec:
     {{- if not .Values.autoscaling.enabled }}
     replicas: {{ .Values.replicaCount }}
     {{- end }}
     selector:
       matchLabels:
         {{- include "platform-api.selectorLabels" . | nindent 6 }}
     template:
       metadata:
         annotations:
           {{- toYaml .Values.podAnnotations | nindent 8 }}
         labels:
           {{- include "platform-api.labels" . | nindent 8 }}
           {{- with .Values.podLabels }}
           {{- toYaml . | nindent 8 }}
           {{- end }}
       spec:
         {{- with .Values.imagePullSecrets }}
         imagePullSecrets:
           {{- toYaml . | nindent 8 }}
         {{- end }}
         serviceAccountName: {{ include "platform-api.serviceAccountName" . }}
         containers:
         - name: {{ .Chart.Name }}
           image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
           imagePullPolicy: {{ .Values.image.pullPolicy }}
           ports:
           - name: {{ .Values.service.name | default "http" }}
             containerPort: {{ .Values.service.targetPort }}
             protocol: TCP
           {{- with .Values.livenessProbe }}
           livenessProbe:
             {{- toYaml . | nindent 12 }}
           {{- end }}
           {{- with .Values.readinessProbe }}
           readinessProbe:
             {{- toYaml . | nindent 12 }}
           {{- end }}
           resources:
             {{- toYaml .Values.resources | nindent 12 }}
           {{- with .Values.env }}
           env:
             {{- toYaml . | nindent 12 }}
           {{- end }}
           {{- with .Values.envFrom }}
           envFrom:
             {{- toYaml . | nindent 12 }}
           {{- end }}
   ```

5. Add an optional ExternalSecret template. Create `platform-api/templates/external-secret.yaml`:

   ```yaml
   {{- if and .Values.secrets.enabled .Values.secrets.externalSecret.enabled }}
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: {{ include "platform-api.fullname" . }}
     labels:
       {{- include "platform-api.labels" . | nindent 4 }}
   spec:
     refreshInterval: {{ .Values.secrets.externalSecret.refreshInterval }}
     secretStoreRef:
       name: {{ .Values.secrets.externalSecret.secretStoreRef.name }}
       kind: {{ .Values.secrets.externalSecret.secretStoreRef.kind }}
     target:
       name: {{ include "platform-api.fullname" . }}-secret
       creationPolicy: Owner
     dataFrom:
     - extract:
         key: {{ .Values.secrets.externalSecret.remoteRef.key }}
   {{- end }}
   ```

6. Add an HPA template. Create `platform-api/templates/hpa.yaml`:

   ```yaml
   {{- if .Values.autoscaling.enabled }}
   apiVersion: autoscaling/v2
   kind: HorizontalPodAutoscaler
   metadata:
     name: {{ include "platform-api.fullname" . }}
     labels:
       {{- include "platform-api.labels" . | nindent 4 }}
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: {{ include "platform-api.fullname" . }}
     minReplicas: {{ .Values.autoscaling.minReplicas }}
     maxReplicas: {{ .Values.autoscaling.maxReplicas }}
     metrics:
     {{- if .Values.autoscaling.targetCPUUtilizationPercentage }}
     - type: Resource
       resource:
         name: cpu
         target:
           type: Utilization
           averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
     {{- end }}
     {{- if .Values.autoscaling.targetMemoryUtilizationPercentage }}
     - type: Resource
       resource:
         name: memory
         target:
           type: Utilization
           averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
     {{- end }}
   {{- end }}
   ```

### Part B: Lint and Template Locally

7. Lint the chart:

   ```bash
   helm lint platform-api/
   ```

8. Render the templates to verify output:

   ```bash
   helm template platform-api platform-api/ --namespace platform-api --debug
   ```

9. Test with custom values:

   ```bash
   helm template platform-api platform-api/ \
     --set image.tag=v2.0.0 \
     --set replicaCount=3 \
     --set secrets.enabled=true \
     --set secrets.externalSecret.enabled=true \
     --set secrets.externalSecret.remoteRef.key=platform-api-secrets
   ```

### Part C: Package and Push as OCI

10. Authenticate Helm to Artifact Registry:

    ```bash
    gcloud auth print-access-token | helm registry login \
      us-central1-docker.pkg.dev \
      --username=oauth2accesstoken \
      --password-stdin
    ```

11. Package the chart:

    ```bash
    helm package platform-api/
    # Creates platform-api-0.1.0.tgz
    ```

12. Push to Artifact Registry as an OCI artifact:

    ```bash
    helm push platform-api-0.1.0.tgz oci://us-central1-docker.pkg.dev/cluster-dreams/helm-charts
    ```

13. Verify the push:

    ```bash
    gcloud artifacts docker images list \
      us-central1-docker.pkg.dev/cluster-dreams/helm-charts \
      --include-tags --project=cluster-dreams

    # Or via Helm
    helm show chart oci://us-central1-docker.pkg.dev/cluster-dreams/helm-charts/platform-api --version 0.1.0
    ```

### Part D: Deploy via ArgoCD GitOps Pipeline

14. Create the application definition for dev. Create `gke-applications/dev/platform-api.yaml`:

    ```yaml
    name: platform-api
    chart: platform-api
    repoURL: us-central1-docker.pkg.dev/cluster-dreams/helm-charts
    targetRevision: "0.1.0"
    namespace: platform-api
    cluster_env: dev
    helm:
      values:
        image:
          repository: nginx
          tag: "1.25"
        service:
          targetPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: http
        readinessProbe:
          httpGet:
            path: /
            port: http
        autoscaling:
          enabled: false
        replicaCount: 1
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            memory: 128Mi
    ```

    Note: For dev we use nginx as a stand-in since we don't have the actual platform-api image yet. The chart is pulled from Artifact Registry via OCI.

15. Commit and merge:

    ```bash
    git add gke-applications/dev/platform-api.yaml
    git commit -m "Deploy platform-api from OCI Artifact Registry to dev"
    git push
    ```

16. After merge, verify in ArgoCD:

    ```bash
    kubectl get applications -n argocd --context=gitops | grep platform-api
    ```

17. Verify on the dev cluster:

    ```bash
    kubectl get pods -n platform-api --context=dev
    kubectl get svc -n platform-api --context=dev
    kubectl get hpa -n platform-api --context=dev
    ```

### Part E: Version Bump and Upgrade

18. Bump the chart version. Edit `platform-api/Chart.yaml`:

    ```yaml
    version: 0.2.0
    appVersion: "1.1.0"
    ```

19. Add a new feature — a ServiceMonitor for Prometheus:

    ```yaml
    # platform-api/templates/servicemonitor.yaml
    {{- if .Values.serviceMonitor.enabled }}
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: {{ include "platform-api.fullname" . }}
      labels:
        {{- include "platform-api.labels" . | nindent 4 }}
        release: prometheus-monitoring
    spec:
      selector:
        matchLabels:
          {{- include "platform-api.selectorLabels" . | nindent 6 }}
      endpoints:
      - port: {{ .Values.service.name | default "http" }}
        interval: 30s
        path: /metrics
    {{- end }}
    ```

    Add to `values.yaml`:

    ```yaml
    serviceMonitor:
      enabled: false
    ```

20. Package and push the new version:

    ```bash
    helm package platform-api/
    helm push platform-api-0.2.0.tgz oci://us-central1-docker.pkg.dev/cluster-dreams/helm-charts
    ```

21. Update the application to use the new version:

    ```bash
    # Edit gke-applications/dev/platform-api.yaml
    # Change targetRevision: "0.1.0" to targetRevision: "0.2.0"
    # Add: serviceMonitor.enabled: true
    ```

22. Commit, push, merge. ArgoCD upgrades the release.

### Part F: Promote Through SDLC

23. After validating in dev, promote to staging and gitops following the same pattern as Task 3 in the intermediate section. Each environment can override values:

    - **dev**: 1 replica, no autoscaling, minimal resources
    - **staging**: 2 replicas, autoscaling enabled, moderate resources
    - **gitops**: 2 replicas, autoscaling enabled, production resources, ESO secrets enabled

## Key Concepts

- **OCI Helm charts**: Helm 3.8+ supports pushing charts to any OCI registry (Docker-format)
- **Artifact Registry**: GCP's managed registry, supports Docker images and OCI artifacts
- **ArgoCD OCI support**: Requires `enableOCI: true` in repository configuration
- **Chart versioning**: Semantic versioning; bump for every change
- **Template best practices**: Make everything configurable via values.yaml
- **ExternalSecret integration**: Charts can optionally create ESO resources for secret management
- **ServiceMonitor integration**: Charts should expose Prometheus metrics and create ServiceMonitors

## Cleanup

```bash
kubectl delete -f gke-applications/dev/platform-api.yaml  # Or remove from git
helm registry logout us-central1-docker.pkg.dev
rm -rf /tmp/helm-charts/platform-api*
```
