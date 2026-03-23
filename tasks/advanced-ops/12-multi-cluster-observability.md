# Task 12: Multi-Cluster Observability — Federated Metrics, Cross-Cluster Dashboards, and Unified Alerting

**Level:** Advanced Operations

**Objective:** Set up Prometheus federation to aggregate metrics from dev and staging clusters into the gitops cluster, build cross-cluster Grafana dashboards for unified visibility, configure centralized alerting, and correlate logs across clusters using Loki.

## Context

This platform runs 3 clusters (dev, staging, gitops), each with their own independent Prometheus and Loki instances. While this works for per-cluster monitoring, platform engineers need:
- A single pane of glass showing all clusters
- Cross-cluster comparisons (is staging performing differently than dev?)
- Centralized alerting (one Alertmanager to rule them all)
- Unified log search across clusters

The gitops cluster is the natural aggregation point since it already manages the other clusters via ArgoCD.

## Steps

### Part A: Understand the Current Setup

1. Verify each cluster has its own monitoring stack:

   ```bash
   for ctx in dev staging gitops; do
     echo "=== $ctx ==="
     kubectl get pods -n monitoring --context=$ctx --no-headers | wc -l
     echo "Prometheus:"
     kubectl get statefulset -n monitoring --context=$ctx -l app.kubernetes.io/name=prometheus -o name
     echo "Alertmanager:"
     kubectl get statefulset -n monitoring --context=$ctx -l app.kubernetes.io/name=alertmanager -o name
     echo ""
   done
   ```

2. Check that each Prometheus is scraping its own cluster:

   ```bash
   for ctx in dev staging gitops; do
     echo "=== $ctx ==="
     kubectl port-forward svc/prometheus-monitoring-kube-prometheus -n monitoring 909${ctx: -1}:9090 --context=$ctx &
   done
   # Note: Run each in the background, then query each port
   ```

### Part B: Configure Prometheus Federation

Prometheus federation allows a "central" Prometheus to scrape selected metrics from "leaf" Prometheus instances. The gitops Prometheus will federate from dev and staging.

3. First, expose the dev and staging Prometheus instances to the gitops cluster. Since all clusters are in the same VPC, you can use internal Services. The dev and staging Prometheus are already accessible within their clusters.

   For cross-cluster federation, you need the Prometheus endpoint accessible from the gitops cluster. Options:
   - **Internal Load Balancer** (recommended for production)
   - **Istio multi-cluster mesh** (if configured)
   - **VPN/private connectivity** (already available in shared VPC)

   Create an internal LoadBalancer for dev Prometheus:

   ```yaml
   # monitoring/federation/dev-prometheus-ilb.yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: prometheus-federation
     namespace: monitoring
     annotations:
       cloud.google.com/load-balancer-type: "Internal"
   spec:
     type: LoadBalancer
     selector:
       app.kubernetes.io/name: prometheus
       prometheus: prometheus-monitoring-kube-prometheus
     ports:
     - port: 9090
       targetPort: 9090
       name: http-prometheus
   ```

4. Apply to dev and staging clusters:

   ```bash
   kubectl apply -f monitoring/federation/dev-prometheus-ilb.yaml --context=dev
   kubectl apply -f monitoring/federation/dev-prometheus-ilb.yaml --context=staging

   # Wait for IPs
   kubectl get svc prometheus-federation -n monitoring --context=dev -w
   kubectl get svc prometheus-federation -n monitoring --context=staging -w

   # Note the EXTERNAL-IP (internal IPs in the VPC)
   DEV_PROM_IP=$(kubectl get svc prometheus-federation -n monitoring --context=dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   STAGING_PROM_IP=$(kubectl get svc prometheus-federation -n monitoring --context=staging -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

   echo "Dev Prometheus: $DEV_PROM_IP"
   echo "Staging Prometheus: $STAGING_PROM_IP"
   ```

5. Configure the gitops Prometheus to federate from dev and staging. Add to `gke-applications/gitops/prometheus.yaml`:

   ```yaml
   helm:
     values:
       prometheus:
         prometheusSpec:
           additionalScrapeConfigs:
           - job_name: 'federate-dev'
             honor_labels: true
             metrics_path: '/federate'
             params:
               'match[]':
               # Federate key metrics (not everything — that would be too much)
               - '{__name__=~"service:.*"}'                    # Recording rules
               - '{__name__=~"kube_pod_status_phase"}'         # Pod phases
               - '{__name__=~"kube_pod_container_status_restarts_total"}'
               - '{__name__=~"container_cpu_usage_seconds_total"}'
               - '{__name__=~"container_memory_working_set_bytes"}'
               - '{__name__=~"istio_requests_total"}'          # Istio traffic
               - '{__name__=~"up"}'                             # Target health
               - '{__name__=~"certmanager_certificate_.*"}'    # Cert health
               - '{__name__=~"kube_deployment_status_.*"}'     # Deployment health
             static_configs:
             - targets:
               - '<DEV_PROMETHEUS_IP>:9090'
               labels:
                 cluster: dev
             scrape_interval: 30s
             scrape_timeout: 25s

           - job_name: 'federate-staging'
             honor_labels: true
             metrics_path: '/federate'
             params:
               'match[]':
               - '{__name__=~"service:.*"}'
               - '{__name__=~"kube_pod_status_phase"}'
               - '{__name__=~"kube_pod_container_status_restarts_total"}'
               - '{__name__=~"container_cpu_usage_seconds_total"}'
               - '{__name__=~"container_memory_working_set_bytes"}'
               - '{__name__=~"istio_requests_total"}'
               - '{__name__=~"up"}'
               - '{__name__=~"certmanager_certificate_.*"}'
               - '{__name__=~"kube_deployment_status_.*"}'
             static_configs:
             - targets:
               - '<STAGING_PROMETHEUS_IP>:9090'
               labels:
                 cluster: staging
             scrape_interval: 30s
             scrape_timeout: 25s
   ```

   Replace `<DEV_PROMETHEUS_IP>` and `<STAGING_PROMETHEUS_IP>` with the IPs from step 4.

6. Verify federation is working:

   ```bash
   # Port-forward gitops Prometheus
   kubectl port-forward svc/prometheus-monitoring-kube-prometheus -n monitoring 9090:9090 --context=gitops

   # Check federated targets
   curl -s http://localhost:9090/api/v1/targets | \
     jq '.data.activeTargets[] | select(.labels.job | test("federate")) | {job: .labels.job, health: .health, cluster: .labels.cluster}'

   # Query a federated metric across clusters
   curl -s 'http://localhost:9090/api/v1/query?query=count(up) by (cluster)' | jq '.data.result'
   ```

### Part C: Cross-Cluster Grafana Dashboard

7. Create a multi-cluster overview dashboard on the gitops Grafana:

   ```yaml
   # monitoring/dashboards/multi-cluster-overview.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: multi-cluster-overview
     namespace: monitoring
     labels:
       grafana_dashboard: "1"
   data:
     multi-cluster.json: |
       {
         "panels": [
           {
             "title": "Pod Count by Cluster",
             "type": "stat",
             "gridPos": { "h": 6, "w": 8, "x": 0, "y": 0 },
             "targets": [
               {
                 "expr": "count(kube_pod_status_phase{phase=\"Running\"}) by (cluster)",
                 "legendFormat": "{{ cluster }}"
               }
             ]
           },
           {
             "title": "Request Rate by Cluster",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 0, "y": 6 },
             "targets": [
               {
                 "expr": "sum(rate(istio_requests_total{reporter=\"destination\"}[5m])) by (cluster)",
                 "legendFormat": "{{ cluster }}"
               }
             ],
             "fieldConfig": { "defaults": { "unit": "reqps" } }
           },
           {
             "title": "Error Rate by Cluster",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 12, "y": 6 },
             "targets": [
               {
                 "expr": "sum(rate(istio_requests_total{response_code=~\"5..\", reporter=\"destination\"}[5m])) by (cluster)",
                 "legendFormat": "{{ cluster }} - 5xx"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "reqps",
                 "color": { "mode": "palette-classic" }
               }
             }
           },
           {
             "title": "CPU Usage by Cluster",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 0, "y": 14 },
             "targets": [
               {
                 "expr": "sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[5m])) by (cluster)",
                 "legendFormat": "{{ cluster }}"
               }
             ],
             "fieldConfig": { "defaults": { "unit": "short" } }
           },
           {
             "title": "Memory Usage by Cluster",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 12, "y": 14 },
             "targets": [
               {
                 "expr": "sum(container_memory_working_set_bytes{container!=\"\"}) by (cluster)",
                 "legendFormat": "{{ cluster }}"
               }
             ],
             "fieldConfig": { "defaults": { "unit": "bytes" } }
           },
           {
             "title": "Pod Restarts by Cluster (Last 1h)",
             "type": "bargauge",
             "gridPos": { "h": 6, "w": 8, "x": 8, "y": 0 },
             "targets": [
               {
                 "expr": "sum(increase(kube_pod_container_status_restarts_total[1h])) by (cluster)",
                 "legendFormat": "{{ cluster }}"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "thresholds": {
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 5 },
                     { "color": "red", "value": 20 }
                   ]
                 }
               }
             }
           },
           {
             "title": "Certificate Health by Cluster",
             "type": "table",
             "gridPos": { "h": 6, "w": 8, "x": 16, "y": 0 },
             "targets": [
               {
                 "expr": "(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400",
                 "format": "table",
                 "instant": true
               }
             ],
             "fieldConfig": {
               "defaults": { "unit": "d" },
               "overrides": [
                 {
                   "matcher": { "id": "byName", "options": "Value" },
                   "properties": [{
                     "id": "thresholds",
                     "value": {
                       "steps": [
                         { "color": "red", "value": null },
                         { "color": "yellow", "value": 14 },
                         { "color": "green", "value": 30 }
                       ]
                     }
                   }]
                 }
               ]
             }
           },
           {
             "title": "Deployment Availability Comparison",
             "type": "table",
             "gridPos": { "h": 8, "w": 24, "x": 0, "y": 22 },
             "targets": [
               {
                 "expr": "kube_deployment_status_available_replicas / kube_deployment_spec_replicas",
                 "format": "table",
                 "instant": true
               }
             ],
             "transformations": [
               {
                 "id": "organize",
                 "options": {
                   "excludeByName": { "Time": true },
                   "renameByName": {
                     "cluster": "Cluster",
                     "namespace": "Namespace",
                     "deployment": "Deployment",
                     "Value": "Availability"
                   }
                 }
               }
             ]
           }
         ],
         "templating": {
           "list": [
             {
               "name": "cluster",
               "type": "query",
               "datasource": "Prometheus",
               "query": "label_values(up, cluster)",
               "includeAll": true,
               "multi": true,
               "refresh": 2
             }
           ]
         },
         "title": "Multi-Cluster Overview",
         "uid": "multi-cluster-overview",
         "version": 1,
         "schemaVersion": 39
       }
   ```

8. Apply to the gitops cluster:

   ```bash
   kubectl apply -f monitoring/dashboards/multi-cluster-overview.yaml --context=gitops
   ```

### Part D: Centralized Alerting

9. Configure the gitops Alertmanager as the central alerting hub. Add cross-cluster alert rules:

   ```yaml
   # monitoring/cross-cluster-alerts.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: cross-cluster-alerting
     namespace: monitoring
     labels:
       release: prometheus-monitoring
   spec:
     groups:
     - name: cross_cluster_health
       rules:
       - alert: ClusterFederationDown
         expr: |
           up{job=~"federate-.*"} == 0
         for: 5m
         labels:
           severity: critical
           team: platform
         annotations:
           summary: "Federation target {{ $labels.cluster }} is down"
           description: >-
             Cannot scrape metrics from the {{ $labels.cluster }} cluster.
             The cluster may be unreachable or the Prometheus instance is down.
             This causes loss of visibility for that cluster.

       - alert: ClusterPodCountDivergence
         expr: |
           abs(
             count(kube_pod_status_phase{phase="Running", cluster="dev"})
             -
             count(kube_pod_status_phase{phase="Running", cluster="staging"})
           ) > 50
         for: 30m
         labels:
           severity: info
           team: platform
         annotations:
           summary: "Large pod count difference between dev and staging"
           description: >-
             Dev and staging clusters differ by more than 50 running pods.
             This may indicate a deployment issue or missing workloads.

       - alert: ClusterHighErrorRateCompared
         expr: |
           (
             sum(rate(istio_requests_total{response_code=~"5..", cluster=~"$cluster"}[5m]))
             /
             sum(rate(istio_requests_total{cluster=~"$cluster"}[5m]))
           ) > 2 * (
             sum(rate(istio_requests_total{response_code=~"5.."}[5m]))
             /
             sum(rate(istio_requests_total[5m]))
           )
         for: 10m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "Cluster {{ $labels.cluster }} error rate is 2x the average"
   ```

10. Apply to the gitops cluster:

    ```bash
    kubectl apply -f monitoring/cross-cluster-alerts.yaml --context=gitops
    ```

### Part E: Cross-Cluster Log Correlation with Loki

11. Configure the gitops Grafana to query Loki across clusters. Add dev and staging Loki as additional datasources:

    ```yaml
    # In gke-applications/gitops/prometheus.yaml, extend grafana config:
    grafana:
      additionalDataSources:
      - name: Loki (gitops)
        access: proxy
        type: loki
        url: http://loki.logging.svc.cluster.local:3100
        jsonData:
          tlsSkipVerify: true
      - name: Loki (dev)
        access: proxy
        type: loki
        url: http://<DEV_LOKI_IP>:3100
        jsonData:
          tlsSkipVerify: true
      - name: Loki (staging)
        access: proxy
        type: loki
        url: http://<STAGING_LOKI_IP>:3100
        jsonData:
          tlsSkipVerify: true
    ```

    Similar to Prometheus, expose Loki via internal LoadBalancers on dev/staging.

12. Use LogQL to search across clusters in Grafana's Explore view:

    ```logql
    # In Grafana → Explore → Select "Loki (dev)" datasource

    # Find errors in a specific namespace
    {namespace="bookinfo"} |= "error" | logfmt

    # Find container restarts
    {namespace="default"} |= "OOMKilled"

    # Search for a specific request ID across clusters
    # Switch between Loki (dev), Loki (staging), Loki (gitops) datasources
    {namespace=~".+"} |= "request-id-abc123"
    ```

### Part F: Monitoring ArgoCD Itself

13. ArgoCD exposes Prometheus metrics. Create a dashboard for ArgoCD health on the gitops cluster:

    ```promql
    # Application sync status
    argocd_app_info{sync_status="Synced"} / argocd_app_info

    # Time since last sync per app
    time() - argocd_app_info * on(name) group_right argocd_app_info{sync_status="Synced"}

    # ArgoCD controller reconciliation duration
    histogram_quantile(0.99, sum(rate(argocd_app_reconcile_bucket[5m])) by (le))

    # Git operations per second
    sum(rate(argocd_git_request_total[5m])) by (request_type)

    # Cluster API server requests
    sum(rate(argocd_cluster_api_resource_actions_total[5m])) by (action, cluster)
    ```

14. Create a ServiceMonitor for ArgoCD (if not already configured):

    ```yaml
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: argocd-metrics
      namespace: argocd
      labels:
        release: prometheus-monitoring
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/part-of: argocd
      namespaceSelector:
        matchNames:
        - argocd
      endpoints:
      - port: metrics
        interval: 30s
    ```

### Part G: Verify End-to-End

15. Verification checklist:

    ```bash
    # 1. Federation health
    curl -s http://localhost:9090/api/v1/targets | \
      jq '[.data.activeTargets[] | select(.labels.job | test("federate"))] | length'
    # Should be 2 (dev + staging)

    # 2. Cross-cluster query works
    curl -s 'http://localhost:9090/api/v1/query?query=count(up) by (cluster)' | jq '.data.result'
    # Should show entries for dev, staging, gitops

    # 3. Dashboard loads
    curl -s -u admin:prom-operator http://localhost:3000/api/dashboards/uid/multi-cluster-overview | jq '.meta.slug'

    # 4. Alert rules loaded
    curl -s http://localhost:9090/api/v1/rules | \
      jq '[.data.groups[].rules[] | select(.name | test("Cluster"))] | length'
    ```

## Architecture

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   dev        │    │   staging    │    │   gitops     │
│              │    │              │    │   (central)  │
│ Prometheus ──┼────┼─ Prometheus ─┼────┼→ Prometheus  │
│ Loki      ──┼────┼─ Loki      ──┼────┼→ Grafana     │
│ Alertmgr    │    │ Alertmgr    │    │ Alertmgr    │
└──────────────┘    └──────────────┘    │ (central)   │
                                        │              │
     /federate endpoint                 │ ArgoCD       │
     (selected metrics only)            │ (manages all)│
                                        └──────────────┘
```

## Key Concepts

- **Prometheus federation**: Central Prometheus scrapes `/federate` endpoint of leaf instances
- **`honor_labels: true`**: Preserves original labels from federated metrics (important for `cluster` label)
- **`match[]` parameter**: Controls which metrics are federated (federate selectively, not everything)
- **`cluster` label**: Added via `static_configs.labels` to distinguish metrics from different clusters
- **Internal LoadBalancer**: GCP internal LB for cross-cluster access within the same VPC
- **Multi-datasource Grafana**: Query different Loki/Prometheus instances from a single Grafana
- **Cross-cluster alerts**: Rules on federated data detect cluster-wide issues
- **ArgoCD metrics**: Monitor the GitOps control plane itself

## Cleanup

```bash
kubectl delete svc prometheus-federation -n monitoring --context=dev
kubectl delete svc prometheus-federation -n monitoring --context=staging
kubectl delete configmap multi-cluster-overview -n monitoring --context=gitops
kubectl delete prometheusrule cross-cluster-alerting -n monitoring --context=gitops
```
