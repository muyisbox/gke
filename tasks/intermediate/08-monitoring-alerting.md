# Task 8: Prometheus Monitoring and Alerting

**Level:** Intermediate

**Objective:** Use the kube-prometheus-stack to query metrics, create dashboards, and understand alerting in this platform.

## Context

Each cluster deploys `kube-prometheus-stack` (chart v82.10.3) with Prometheus (2 replicas, 10Gi storage), Alertmanager (2 replicas, 5Gi storage), and Grafana with a pre-configured Loki datasource.

## Steps

### Part A: Access the Monitoring Stack

1. Port-forward Grafana:

   ```bash
   kubectl port-forward svc/prometheus-monitoring-grafana -n monitoring 3000:80
   ```

   Login: `admin` / `prom-operator`

2. Port-forward Prometheus:

   ```bash
   kubectl port-forward svc/prometheus-monitoring-kube-prometheus -n monitoring 9090:9090
   ```

### Part B: Investigate Cluster Health

3. In Prometheus, run these queries:

   ```promql
   # Node CPU utilization percentage
   100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

   # Memory pressure per node
   (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

   # Top 10 pods by memory
   topk(10, container_memory_working_set_bytes{container!=""})

   # Pods exceeding their memory requests
   (container_memory_working_set_bytes{container!=""} / on(namespace,pod,container) kube_pod_container_resource_requests{resource="memory"}) > 1

   # Pod restart rate (which pods are unstable?)
   rate(kube_pod_container_status_restarts_total[10m]) * 60 * 10
   ```

4. In Grafana, find the dashboard "Kubernetes / Compute Resources / Namespace (Pods)":
   - Which namespace uses the most CPU?
   - Which namespace uses the most memory?

### Part C: Query Istio Metrics

5. Istio exports metrics to Prometheus. Try these:

   ```promql
   # Request rate per service
   rate(istio_requests_total[5m])

   # 99th percentile latency for bookinfo
   histogram_quantile(0.99, rate(istio_request_duration_milliseconds_bucket{destination_service_namespace="bookinfo"}[5m]))

   # Error rate (5xx responses)
   rate(istio_requests_total{response_code=~"5.."}[5m])
   ```

### Part D: Explore Logs with Loki

6. In Grafana, go to Explore → select "Loki" datasource.

7. Query istiod logs:

   ```logql
   {namespace="istio-system", app="istiod"}
   ```

8. Find errors across all namespaces:

   ```logql
   {namespace=~".+"} |= "error" | logfmt
   ```

9. Check `gke-applications/dev/prometheus-monitoring.yaml` — how is the Loki datasource configured? What URL does Grafana use to reach Loki?

### Part E: Understand ServiceMonitors

10. The platform uses ServiceMonitors to tell Prometheus what to scrape. Check which exist:

    ```bash
    kubectl get servicemonitors -A
    ```

11. Check the cert-manager ServiceMonitor:

    ```bash
    kubectl get servicemonitor -n cert-manager -o yaml
    ```

    What label selector does Prometheus use to find ServiceMonitors? (Hint: check `release: prometheus-monitoring` in the app configs)

### Part F: Alertmanager

12. Port-forward Alertmanager:

    ```bash
    kubectl port-forward svc/prometheus-monitoring-kube-alertmanager -n monitoring 9093:9093
    ```

13. Open `http://localhost:9093` — are there any active alerts?

14. List PrometheusRule objects (alert definitions):

    ```bash
    kubectl get prometheusrules -n monitoring
    ```

## Key Concepts

- **Prometheus**: Scrapes metrics from pods via ServiceMonitors
- **Grafana**: Visualization layer, connects to both Prometheus and Loki
- **Loki**: Log aggregation, queryable via LogQL
- **ServiceMonitor**: CRD that tells Prometheus what to scrape
- **Alertmanager**: Receives alerts from Prometheus, handles routing and notification
- Apps opt-in to monitoring by creating a ServiceMonitor with the label `release: prometheus-monitoring`
