# Task 8: Build Production Grafana Dashboards with Templating and GitOps

**Level:** Advanced Operations

**Objective:** Create custom Grafana dashboards using the RED method (Rate, Errors, Duration), implement dashboard templating with variables for multi-cluster and multi-namespace views, export dashboards as JSON ConfigMaps, and deploy them through the GitOps pipeline.

## Context

The kube-prometheus-stack (v82.10.3) includes Grafana with many pre-built dashboards for infrastructure monitoring. However, platform teams need custom dashboards for:
- Application-level observability (services behind Istio mesh)
- Team-specific views with namespace filtering
- SLO tracking (error budgets, availability targets)
- Cross-cluster comparison (dev vs staging vs gitops)

Grafana dashboards can be provisioned as ConfigMaps with the label `grafana_dashboard: "1"`, which the Grafana sidecar automatically detects and loads.

## Steps

### Part A: Access Grafana and Explore Existing Dashboards

1. Port-forward to Grafana:

   ```bash
   kubectl port-forward svc/prometheus-monitoring-grafana -n monitoring 3000:80 --context=dev
   ```

   Default credentials: `admin` / `prom-operator`

2. Explore the pre-built dashboards:

   ```bash
   # List all dashboards via the API
   curl -s -u admin:prom-operator http://localhost:3000/api/search?type=dash-db | jq '.[].title'
   ```

   Key built-in dashboards to study:
   - **Kubernetes / Compute Resources / Namespace (Pods)** — Resource usage per pod
   - **Kubernetes / Networking / Namespace** — Network traffic
   - **Node Exporter / Nodes** — Host-level metrics

3. Understand how dashboards are provisioned. The Grafana sidecar watches for ConfigMaps:

   ```bash
   kubectl get configmaps -n monitoring --context=dev -l grafana_dashboard=1
   ```

### Part B: Create a Service Overview Dashboard (RED Method)

The RED method tracks three golden signals for every service:
- **Rate**: Request throughput
- **Errors**: Error rate or ratio
- **Duration**: Latency distribution

4. Create the dashboard JSON. This dashboard uses Istio metrics available in the mesh:

   ```yaml
   # monitoring/dashboards/service-overview-dashboard.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: service-overview-dashboard
     namespace: monitoring
     labels:
       grafana_dashboard: "1"
   data:
     service-overview.json: |
       {
         "annotations": {
           "list": []
         },
         "editable": true,
         "fiscalYearStartMonth": 0,
         "graphTooltip": 1,
         "links": [],
         "panels": [
           {
             "title": "Request Rate (req/s)",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
             "targets": [
               {
                 "expr": "sum(rate(istio_requests_total{destination_service_namespace=~\"$namespace\", reporter=\"destination\"}[5m])) by (destination_service_name)",
                 "legendFormat": "{{ destination_service_name }}"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "reqps",
                 "custom": {
                   "drawStyle": "line",
                   "lineWidth": 2,
                   "fillOpacity": 10,
                   "showPoints": "never"
                 }
               }
             }
           },
           {
             "title": "Error Rate (5xx)",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
             "targets": [
               {
                 "expr": "sum(rate(istio_requests_total{destination_service_namespace=~\"$namespace\", response_code=~\"5..\", reporter=\"destination\"}[5m])) by (destination_service_name)",
                 "legendFormat": "{{ destination_service_name }} - 5xx"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "reqps",
                 "custom": {
                   "drawStyle": "line",
                   "lineWidth": 2,
                   "fillOpacity": 10
                 },
                 "color": { "mode": "palette-classic" },
                 "thresholds": {
                   "mode": "absolute",
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 0.01 },
                     { "color": "red", "value": 0.1 }
                   ]
                 }
               }
             }
           },
           {
             "title": "Error Ratio (%)",
             "type": "gauge",
             "gridPos": { "h": 8, "w": 6, "x": 0, "y": 8 },
             "targets": [
               {
                 "expr": "sum(rate(istio_requests_total{destination_service_namespace=~\"$namespace\", response_code=~\"5..\", reporter=\"destination\"}[5m])) / sum(rate(istio_requests_total{destination_service_namespace=~\"$namespace\", reporter=\"destination\"}[5m]))",
                 "legendFormat": "Error Ratio"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "percentunit",
                 "thresholds": {
                   "mode": "absolute",
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 0.01 },
                     { "color": "red", "value": 0.05 }
                   ]
                 },
                 "min": 0,
                 "max": 1
               }
             }
           },
           {
             "title": "P99 Latency",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 18, "x": 6, "y": 8 },
             "targets": [
               {
                 "expr": "histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_service_namespace=~\"$namespace\", reporter=\"destination\"}[5m])) by (destination_service_name, le)) / 1000",
                 "legendFormat": "{{ destination_service_name }} - p99"
               },
               {
                 "expr": "histogram_quantile(0.95, sum(rate(istio_request_duration_milliseconds_bucket{destination_service_namespace=~\"$namespace\", reporter=\"destination\"}[5m])) by (destination_service_name, le)) / 1000",
                 "legendFormat": "{{ destination_service_name }} - p95"
               },
               {
                 "expr": "histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{destination_service_namespace=~\"$namespace\", reporter=\"destination\"}[5m])) by (destination_service_name, le)) / 1000",
                 "legendFormat": "{{ destination_service_name }} - p50"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "s",
                 "custom": {
                   "drawStyle": "line",
                   "lineWidth": 2,
                   "fillOpacity": 5
                 }
               }
             }
           },
           {
             "title": "Active Pods by Namespace",
             "type": "stat",
             "gridPos": { "h": 4, "w": 24, "x": 0, "y": 16 },
             "targets": [
               {
                 "expr": "count(kube_pod_status_phase{namespace=~\"$namespace\", phase=\"Running\"}) by (namespace)",
                 "legendFormat": "{{ namespace }}"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "short"
               }
             }
           },
           {
             "title": "Pod Restarts (Last 1h)",
             "type": "table",
             "gridPos": { "h": 8, "w": 24, "x": 0, "y": 20 },
             "targets": [
               {
                 "expr": "topk(10, increase(kube_pod_container_status_restarts_total{namespace=~\"$namespace\"}[1h])) > 0",
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
                     "namespace": "Namespace",
                     "pod": "Pod",
                     "container": "Container",
                     "Value": "Restarts"
                   }
                 }
               }
             ]
           }
         ],
         "templating": {
           "list": [
             {
               "name": "namespace",
               "type": "query",
               "datasource": "Prometheus",
               "query": "label_values(kube_namespace_created, namespace)",
               "includeAll": true,
               "allValue": ".*",
               "multi": true,
               "current": {
                 "text": "All",
                 "value": "$__all"
               },
               "refresh": 2
             }
           ]
         },
         "time": { "from": "now-1h", "to": "now" },
         "title": "Service Overview (RED Method)",
         "uid": "service-overview-red",
         "version": 1,
         "schemaVersion": 39
       }
   ```

5. Apply and verify:

   ```bash
   kubectl apply -f monitoring/dashboards/service-overview-dashboard.yaml --context=dev

   # Grafana sidecar picks it up within ~60 seconds
   # Verify in Grafana UI: Dashboards → Browse → "Service Overview (RED Method)"
   ```

### Part C: Create a Namespace Resource Dashboard

6. Create a dashboard focused on resource utilization per namespace:

   ```yaml
   # monitoring/dashboards/namespace-resources-dashboard.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: namespace-resources-dashboard
     namespace: monitoring
     labels:
       grafana_dashboard: "1"
   data:
     namespace-resources.json: |
       {
         "panels": [
           {
             "title": "CPU Usage vs Requests by Namespace",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
             "targets": [
               {
                 "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=~\"$namespace\", container!=\"\"}[5m])) by (namespace)",
                 "legendFormat": "{{ namespace }} - Used"
               },
               {
                 "expr": "sum(kube_pod_container_resource_requests{namespace=~\"$namespace\", resource=\"cpu\"}) by (namespace)",
                 "legendFormat": "{{ namespace }} - Requested"
               }
             ],
             "fieldConfig": { "defaults": { "unit": "short" } }
           },
           {
             "title": "Memory Usage vs Requests by Namespace",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
             "targets": [
               {
                 "expr": "sum(container_memory_working_set_bytes{namespace=~\"$namespace\", container!=\"\"}) by (namespace)",
                 "legendFormat": "{{ namespace }} - Used"
               },
               {
                 "expr": "sum(kube_pod_container_resource_requests{namespace=~\"$namespace\", resource=\"memory\"}) by (namespace)",
                 "legendFormat": "{{ namespace }} - Requested"
               }
             ],
             "fieldConfig": { "defaults": { "unit": "bytes" } }
           },
           {
             "title": "ResourceQuota Utilization",
             "type": "bargauge",
             "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 },
             "targets": [
               {
                 "expr": "kube_resourcequota{namespace=~\"$namespace\", type=\"used\"} / kube_resourcequota{namespace=~\"$namespace\", type=\"hard\"}",
                 "legendFormat": "{{ namespace }} - {{ resource }}"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "percentunit",
                 "thresholds": {
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 0.7 },
                     { "color": "red", "value": 0.9 }
                   ]
                 },
                 "min": 0, "max": 1
               }
             }
           },
           {
             "title": "PVC Usage",
             "type": "bargauge",
             "gridPos": { "h": 8, "w": 24, "x": 0, "y": 16 },
             "targets": [
               {
                 "expr": "kubelet_volume_stats_used_bytes{namespace=~\"$namespace\"} / kubelet_volume_stats_capacity_bytes{namespace=~\"$namespace\"}",
                 "legendFormat": "{{ namespace }}/{{ persistentvolumeclaim }}"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "percentunit",
                 "thresholds": {
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 0.7 },
                     { "color": "red", "value": 0.85 }
                   ]
                 }
               }
             }
           }
         ],
         "templating": {
           "list": [
             {
               "name": "namespace",
               "type": "query",
               "datasource": "Prometheus",
               "query": "label_values(kube_namespace_created, namespace)",
               "includeAll": true,
               "allValue": ".*",
               "multi": true,
               "refresh": 2
             }
           ]
         },
         "title": "Namespace Resource Utilization",
         "uid": "namespace-resources",
         "version": 1,
         "schemaVersion": 39
       }
   ```

### Part D: Create an SLO Tracking Dashboard

7. Create a dashboard that tracks Service Level Objectives:

   ```yaml
   # monitoring/dashboards/slo-dashboard.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: slo-dashboard
     namespace: monitoring
     labels:
       grafana_dashboard: "1"
   data:
     slo-tracking.json: |
       {
         "panels": [
           {
             "title": "Availability SLO (Target: 99.9%)",
             "type": "gauge",
             "gridPos": { "h": 8, "w": 8, "x": 0, "y": 0 },
             "targets": [
               {
                 "expr": "1 - (sum(rate(istio_requests_total{response_code=~\"5..\", destination_service_name=~\"$service\", reporter=\"destination\"}[${__range}])) / sum(rate(istio_requests_total{destination_service_name=~\"$service\", reporter=\"destination\"}[${__range}])))",
                 "legendFormat": "Availability"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "percentunit",
                 "thresholds": {
                   "steps": [
                     { "color": "red", "value": null },
                     { "color": "yellow", "value": 0.999 },
                     { "color": "green", "value": 0.9999 }
                   ]
                 },
                 "min": 0.99, "max": 1
               }
             }
           },
           {
             "title": "Error Budget Remaining (30d window)",
             "type": "stat",
             "gridPos": { "h": 8, "w": 8, "x": 8, "y": 0 },
             "targets": [
               {
                 "expr": "1 - ((1 - (sum(rate(istio_requests_total{response_code=~\"5..\", destination_service_name=~\"$service\", reporter=\"destination\"}[30d])) / sum(rate(istio_requests_total{destination_service_name=~\"$service\", reporter=\"destination\"}[30d])))) / 0.999)",
                 "legendFormat": "Budget Remaining"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "percentunit",
                 "thresholds": {
                   "steps": [
                     { "color": "red", "value": null },
                     { "color": "yellow", "value": 0.25 },
                     { "color": "green", "value": 0.5 }
                   ]
                 }
               }
             }
           },
           {
             "title": "Latency SLO (P99 < 500ms)",
             "type": "gauge",
             "gridPos": { "h": 8, "w": 8, "x": 16, "y": 0 },
             "targets": [
               {
                 "expr": "histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_service_name=~\"$service\", reporter=\"destination\"}[5m])) by (le)) / 1000",
                 "legendFormat": "P99 Latency"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "s",
                 "thresholds": {
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 0.3 },
                     { "color": "red", "value": 0.5 }
                   ]
                 },
                 "min": 0, "max": 1
               }
             }
           },
           {
             "title": "Error Budget Burn Rate (1h vs 6h)",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 },
             "targets": [
               {
                 "expr": "(sum(rate(istio_requests_total{response_code=~\"5..\", destination_service_name=~\"$service\", reporter=\"destination\"}[1h])) / sum(rate(istio_requests_total{destination_service_name=~\"$service\", reporter=\"destination\"}[1h]))) / (1 - 0.999)",
                 "legendFormat": "1h burn rate"
               },
               {
                 "expr": "(sum(rate(istio_requests_total{response_code=~\"5..\", destination_service_name=~\"$service\", reporter=\"destination\"}[6h])) / sum(rate(istio_requests_total{destination_service_name=~\"$service\", reporter=\"destination\"}[6h]))) / (1 - 0.999)",
                 "legendFormat": "6h burn rate"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "custom": { "drawStyle": "line", "lineWidth": 2 },
                 "thresholds": {
                   "mode": "absolute",
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 1 },
                     { "color": "red", "value": 14.4 }
                   ]
                 }
               }
             }
           }
         ],
         "templating": {
           "list": [
             {
               "name": "service",
               "type": "query",
               "datasource": "Prometheus",
               "query": "label_values(istio_requests_total{reporter=\"destination\"}, destination_service_name)",
               "includeAll": true,
               "allValue": ".*",
               "multi": false,
               "refresh": 2
             }
           ]
         },
         "title": "SLO Tracking Dashboard",
         "uid": "slo-tracking",
         "version": 1,
         "schemaVersion": 39
       }
   ```

### Part E: Export and Version Dashboards

8. Export a dashboard you've built or modified in the Grafana UI:

   ```bash
   # Export via API
   DASHBOARD_UID="service-overview-red"
   curl -s -u admin:prom-operator \
     "http://localhost:3000/api/dashboards/uid/${DASHBOARD_UID}" | \
     jq '.dashboard' > /tmp/exported-dashboard.json
   ```

9. Wrap the exported JSON into a ConfigMap for GitOps:

   ```bash
   kubectl create configmap my-dashboard \
     --from-file=dashboard.json=/tmp/exported-dashboard.json \
     --dry-run=client -o yaml | \
     kubectl label --local -f - grafana_dashboard=1 -o yaml > monitoring/dashboards/my-dashboard.yaml
   ```

10. Verify all dashboards are loaded:

    ```bash
    # Count dashboards
    curl -s -u admin:prom-operator http://localhost:3000/api/search?type=dash-db | jq 'length'

    # List custom dashboards
    curl -s -u admin:prom-operator http://localhost:3000/api/search?type=dash-db | \
      jq '.[] | select(.uid | test("service-overview|namespace-resources|slo-tracking")) | .title'
    ```

### Part F: Deploy Dashboards via ArgoCD

11. For production, deploy dashboards as part of the prometheus-monitoring Helm release. Add Grafana dashboard ConfigMaps to the kube-prometheus-stack values:

    ```yaml
    # In gke-applications/dev/prometheus.yaml, add under helm.values:
    grafana:
      dashboardsConfigMaps:
        service-overview: "service-overview-dashboard"
        namespace-resources: "namespace-resources-dashboard"
        slo-tracking: "slo-dashboard"
    ```

    Or deploy dashboards as a separate ArgoCD application using the `raw` Helm chart (as shown in Part B, step 5 pattern).

12. Promote dashboards through SDLC by copying ConfigMaps to staging and gitops environments.

## Key Concepts

- **RED method**: Rate, Errors, Duration — the three golden signals for service monitoring
- **Grafana sidecar**: Watches ConfigMaps with `grafana_dashboard: "1"` label and auto-loads them
- **Dashboard templating**: Variables (e.g., `$namespace`, `$service`) enable reusable, filterable dashboards
- **Error budget**: Remaining tolerance for errors before violating SLO (e.g., 99.9% = 0.1% budget)
- **Burn rate**: How fast the error budget is being consumed (>1 means burning faster than budget allows)
- **Dashboard-as-code**: JSON ConfigMaps deployed via GitOps ensure dashboards are versioned and reproducible
- **`${__range}`**: Grafana built-in variable that reflects the dashboard time range selection

## Cleanup

```bash
kubectl delete configmap service-overview-dashboard namespace-resources-dashboard slo-dashboard -n monitoring --context=dev
```
