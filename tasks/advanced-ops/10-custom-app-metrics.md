# Task 10: Instrument a Custom Application with Prometheus Metrics and ServiceMonitors

**Level:** Advanced Operations

**Objective:** Build and deploy a sample application that exposes custom Prometheus metrics, create a ServiceMonitor to enable scraping, write PrometheusRules for application-specific alerts, and build a Grafana dashboard — completing the full observability loop.

## Context

Most platform monitoring covers infrastructure (node CPU, pod restarts, API server latency). However, application-level metrics are where business value lives:
- Request latency per endpoint
- Database query times
- Queue depth and processing rate
- Cache hit ratios
- Business KPIs (orders placed, users registered)

This task demonstrates the full instrumentation pipeline: app exposes `/metrics` → ServiceMonitor discovers it → Prometheus scrapes it → PrometheusRules alert on it → Grafana visualizes it.

## Steps

### Part A: Deploy a Metrics-Instrumented Application

1. Create a sample application that exposes Prometheus metrics. This uses a pre-built image that exposes custom metrics:

   ```yaml
   # monitoring/sample-app/deployment.yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: metrics-demo
     namespace: default
     labels:
       app: metrics-demo
       team: platform
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: metrics-demo
     template:
       metadata:
         labels:
           app: metrics-demo
           team: platform
         annotations:
           sidecar.istio.io/inject: "true"
       spec:
         containers:
         - name: metrics-demo
           image: quay.io/brancz/prometheus-example-app:v0.5.0
           ports:
           - name: http
             containerPort: 8080
           - name: metrics
             containerPort: 8080
           resources:
             requests:
               cpu: 50m
               memory: 64Mi
             limits:
               memory: 128Mi
           livenessProbe:
             httpGet:
               path: /healthz
               port: 8080
             initialDelaySeconds: 5
           readinessProbe:
             httpGet:
               path: /healthz
               port: 8080
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: metrics-demo
     namespace: default
     labels:
       app: metrics-demo
       team: platform
   spec:
     selector:
       app: metrics-demo
     ports:
     - name: http
       port: 80
       targetPort: 8080
     - name: metrics
       port: 8080
       targetPort: 8080
   ```

2. Deploy and verify the metrics endpoint:

   ```bash
   kubectl apply -f monitoring/sample-app/deployment.yaml --context=dev

   # Wait for pods to be ready
   kubectl wait --for=condition=ready pod -l app=metrics-demo -n default --context=dev --timeout=60s

   # Port-forward and check the metrics endpoint
   kubectl port-forward svc/metrics-demo -n default 8080:8080 --context=dev

   # In another terminal, view raw Prometheus metrics
   curl -s http://localhost:8080/metrics | head -30
   ```

   You should see metrics like:
   ```
   # HELP http_requests_total Total number of HTTP requests
   # TYPE http_requests_total counter
   http_requests_total{code="200",method="get"} 42
   # HELP version App version info
   # TYPE version gauge
   version{version="v0.5.0"} 1
   ```

3. Generate some traffic to populate metrics:

   ```bash
   # Generate traffic (run for 30 seconds)
   for i in $(seq 1 100); do
     curl -s http://localhost:8080/ > /dev/null
     curl -s http://localhost:8080/err > /dev/null 2>&1  # Generate some errors
     sleep 0.3
   done
   ```

### Part B: Create a ServiceMonitor

The ServiceMonitor CRD tells Prometheus Operator which services to scrape and how.

4. Create a ServiceMonitor for the demo app:

   ```yaml
   # monitoring/sample-app/servicemonitor.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: metrics-demo
     namespace: default
     labels:
       release: prometheus-monitoring  # Required for Prometheus to discover this
       app: metrics-demo
   spec:
     selector:
       matchLabels:
         app: metrics-demo
     namespaceSelector:
       matchNames:
       - default
     endpoints:
     - port: metrics
       interval: 15s
       path: /metrics
       scrapeTimeout: 10s
       metricRelabelings:
       # Drop high-cardinality Go runtime metrics to save storage
       - sourceLabels: [__name__]
         regex: 'go_.*'
         action: drop
   ```

5. Apply and verify Prometheus discovers the target:

   ```bash
   kubectl apply -f monitoring/sample-app/servicemonitor.yaml --context=dev

   # Verify the ServiceMonitor is created
   kubectl get servicemonitor metrics-demo -n default --context=dev

   # Port-forward to Prometheus and check targets
   kubectl port-forward svc/prometheus-monitoring-kube-prometheus -n monitoring 9090:9090 --context=dev

   # Check if the target appears (may take 30-60 seconds)
   curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "metrics-demo") | {job: .labels.job, health: .health, lastScrape: .lastScrape}'
   ```

   The target should show `health: "up"`.

6. Query the custom metrics in Prometheus:

   ```bash
   # Total HTTP requests
   curl -s 'http://localhost:9090/api/v1/query?query=http_requests_total{job="metrics-demo"}' | jq '.data.result'

   # Request rate
   curl -s 'http://localhost:9090/api/v1/query?query=rate(http_requests_total{job="metrics-demo"}[5m])' | jq '.data.result'
   ```

### Part C: Create Application-Specific PrometheusRules

7. Create alerting and recording rules for the demo application:

   ```yaml
   # monitoring/sample-app/prometheusrules.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: metrics-demo-rules
     namespace: monitoring
     labels:
       release: prometheus-monitoring
   spec:
     groups:
     - name: metrics_demo_recording
       interval: 15s
       rules:
       # Request rate by status code
       - record: metrics_demo:http_requests:rate5m
         expr: sum(rate(http_requests_total{job="metrics-demo"}[5m])) by (code, method)

       # Error ratio
       - record: metrics_demo:http_error_ratio:rate5m
         expr: |
           sum(rate(http_requests_total{job="metrics-demo", code!="200"}[5m]))
           /
           sum(rate(http_requests_total{job="metrics-demo"}[5m]))

     - name: metrics_demo_alerts
       rules:
       # High error rate for the demo app
       - alert: MetricsDemoHighErrorRate
         expr: |
           metrics_demo:http_error_ratio:rate5m > 0.1
         for: 5m
         labels:
           severity: warning
           team: platform
           app: metrics-demo
         annotations:
           summary: "metrics-demo error rate is above 10%"
           description: >-
             The metrics-demo application has an error rate of
             {{ $value | humanizePercentage }}. Check application logs
             and downstream dependencies.

       # No requests (app might be down or unreachable)
       - alert: MetricsDemoNoTraffic
         expr: |
           sum(rate(http_requests_total{job="metrics-demo"}[5m])) == 0
         for: 10m
         labels:
           severity: info
           team: platform
           app: metrics-demo
         annotations:
           summary: "metrics-demo has received no traffic for 10 minutes"
           description: >-
             The metrics-demo application has not received any HTTP requests
             in the last 10 minutes. Verify the service is healthy and
             traffic routing is correct.

       # Scrape target down
       - alert: MetricsDemoTargetDown
         expr: |
           up{job="metrics-demo"} == 0
         for: 2m
         labels:
           severity: warning
           team: platform
           app: metrics-demo
         annotations:
           summary: "metrics-demo scrape target is down"
           description: >-
             Prometheus cannot scrape metrics from metrics-demo.
             The application may be down or the ServiceMonitor
             configuration may be incorrect.
   ```

8. Apply and verify:

   ```bash
   kubectl apply -f monitoring/sample-app/prometheusrules.yaml --context=dev

   # Check the rules are loaded in Prometheus
   curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name | test("metrics_demo")) | {name: .name, rules: [.rules[].name]}'
   ```

### Part D: Build a Grafana Dashboard for the App

9. Create a ConfigMap dashboard for the demo app:

   ```yaml
   # monitoring/sample-app/dashboard.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: metrics-demo-dashboard
     namespace: monitoring
     labels:
       grafana_dashboard: "1"
   data:
     metrics-demo.json: |
       {
         "panels": [
           {
             "title": "Request Rate by Status Code",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
             "targets": [
               {
                 "expr": "sum(rate(http_requests_total{job=\"metrics-demo\"}[5m])) by (code)",
                 "legendFormat": "HTTP {{ code }}"
               }
             ],
             "fieldConfig": {
               "defaults": { "unit": "reqps" },
               "overrides": [
                 {
                   "matcher": { "id": "byRegexp", "options": ".*[45]\\d\\d.*" },
                   "properties": [{ "id": "color", "value": { "fixedColor": "red", "mode": "fixed" } }]
                 }
               ]
             }
           },
           {
             "title": "Error Ratio",
             "type": "stat",
             "gridPos": { "h": 8, "w": 6, "x": 12, "y": 0 },
             "targets": [
               {
                 "expr": "metrics_demo:http_error_ratio:rate5m or vector(0)",
                 "legendFormat": "Error Ratio"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "unit": "percentunit",
                 "thresholds": {
                   "steps": [
                     { "color": "green", "value": null },
                     { "color": "yellow", "value": 0.01 },
                     { "color": "red", "value": 0.05 }
                   ]
                 }
               }
             }
           },
           {
             "title": "Active Pods",
             "type": "stat",
             "gridPos": { "h": 8, "w": 6, "x": 18, "y": 0 },
             "targets": [
               {
                 "expr": "count(up{job=\"metrics-demo\"} == 1)",
                 "legendFormat": "Healthy"
               },
               {
                 "expr": "count(up{job=\"metrics-demo\"} == 0)",
                 "legendFormat": "Down"
               }
             ],
             "fieldConfig": {
               "defaults": {
                 "thresholds": {
                   "steps": [
                     { "color": "red", "value": null },
                     { "color": "green", "value": 1 }
                   ]
                 }
               }
             }
           },
           {
             "title": "Total Requests (Counter)",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 },
             "targets": [
               {
                 "expr": "sum(http_requests_total{job=\"metrics-demo\"}) by (code, method)",
                 "legendFormat": "{{ method }} {{ code }}"
               }
             ],
             "fieldConfig": {
               "defaults": { "unit": "short" }
             }
           },
           {
             "title": "Pod Resource Usage",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 0, "y": 16 },
             "targets": [
               {
                 "expr": "sum(rate(container_cpu_usage_seconds_total{pod=~\"metrics-demo.*\", container=\"metrics-demo\"}[5m])) by (pod)",
                 "legendFormat": "{{ pod }} - CPU"
               }
             ],
             "fieldConfig": {
               "defaults": { "unit": "short" }
             }
           },
           {
             "title": "Pod Memory Usage",
             "type": "timeseries",
             "gridPos": { "h": 8, "w": 12, "x": 12, "y": 16 },
             "targets": [
               {
                 "expr": "sum(container_memory_working_set_bytes{pod=~\"metrics-demo.*\", container=\"metrics-demo\"}) by (pod)",
                 "legendFormat": "{{ pod }}"
               }
             ],
             "fieldConfig": {
               "defaults": { "unit": "bytes" }
             }
           }
         ],
         "title": "Metrics Demo Application",
         "uid": "metrics-demo-app",
         "version": 1,
         "schemaVersion": 39,
         "time": { "from": "now-1h", "to": "now" }
       }
   ```

10. Apply and verify:

    ```bash
    kubectl apply -f monitoring/sample-app/dashboard.yaml --context=dev

    # Check in Grafana UI → Dashboards → Browse → "Metrics Demo Application"
    ```

### Part E: Write Your Own Instrumented App (Exercise)

11. For a deeper understanding, create a minimal Python app with custom business metrics:

    ```python
    # monitoring/sample-app/custom-app/app.py
    from prometheus_client import Counter, Histogram, Gauge, start_http_server
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import random, time

    # Define custom metrics
    REQUEST_COUNT = Counter(
        'myapp_requests_total',
        'Total requests processed',
        ['method', 'endpoint', 'status']
    )

    REQUEST_LATENCY = Histogram(
        'myapp_request_duration_seconds',
        'Request latency in seconds',
        ['endpoint'],
        buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
    )

    ITEMS_IN_QUEUE = Gauge(
        'myapp_queue_depth',
        'Number of items waiting in queue'
    )

    CACHE_HITS = Counter(
        'myapp_cache_hits_total',
        'Cache hit/miss counter',
        ['result']  # hit or miss
    )

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            start = time.time()

            # Simulate processing
            if self.path == '/api/orders':
                time.sleep(random.uniform(0.01, 0.2))
                status = 200 if random.random() > 0.05 else 500
                # Simulate cache
                if random.random() > 0.3:
                    CACHE_HITS.labels(result='hit').inc()
                else:
                    CACHE_HITS.labels(result='miss').inc()
            elif self.path == '/healthz':
                status = 200
            else:
                status = 404

            REQUEST_COUNT.labels(
                method='GET', endpoint=self.path, status=str(status)
            ).inc()
            REQUEST_LATENCY.labels(endpoint=self.path).observe(time.time() - start)

            # Simulate queue fluctuation
            ITEMS_IN_QUEUE.set(random.randint(0, 50))

            self.send_response(status)
            self.end_headers()

        def log_message(self, format, *args):
            pass  # Suppress default logging

    if __name__ == '__main__':
        # Start metrics server on port 9090
        start_http_server(9090)
        print("Metrics available on :9090/metrics")

        # Start app server on port 8080
        server = HTTPServer(('', 8080), Handler)
        print("App listening on :8080")
        server.serve_forever()
    ```

    Package this in a Dockerfile, push to Artifact Registry (see Task 2), and deploy with a ServiceMonitor that scrapes port 9090.

### Part F: Metric Types Deep Dive

12. Understand the four Prometheus metric types through the demo app:

    ```bash
    # With port-forward active to the metrics endpoint:

    # COUNTER — monotonically increasing (requests, errors, bytes sent)
    curl -s http://localhost:8080/metrics | grep "^http_requests_total"

    # GAUGE — can go up or down (queue depth, temperature, active connections)
    curl -s http://localhost:8080/metrics | grep "^myapp_queue_depth"

    # HISTOGRAM — distribution of values in buckets (latency, request size)
    curl -s http://localhost:8080/metrics | grep "^myapp_request_duration"
    # Note: _bucket, _sum, _count suffixes

    # SUMMARY — similar to histogram but calculates quantiles client-side
    # (Not commonly used; histograms are preferred for aggregation)
    ```

    Key PromQL patterns for each type:

    ```promql
    # Counter → use rate() to get per-second increase
    rate(http_requests_total[5m])

    # Gauge → use directly, or avg_over_time() for smoothing
    myapp_queue_depth
    avg_over_time(myapp_queue_depth[5m])

    # Histogram → use histogram_quantile() for percentiles
    histogram_quantile(0.99, rate(myapp_request_duration_seconds_bucket[5m]))

    # Histogram → use _sum/_count for average
    rate(myapp_request_duration_seconds_sum[5m]) / rate(myapp_request_duration_seconds_count[5m])
    ```

### Part G: ServiceMonitor Advanced Configuration

13. Explore advanced ServiceMonitor features:

    ```yaml
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: advanced-example
      namespace: default
      labels:
        release: prometheus-monitoring
    spec:
      selector:
        matchLabels:
          app: my-app
      endpoints:
      - port: metrics
        interval: 15s
        path: /metrics

        # Basic auth for protected metrics endpoints
        basicAuth:
          username:
            name: metrics-auth
            key: username
          password:
            name: metrics-auth
            key: password

        # TLS configuration
        scheme: https
        tlsConfig:
          insecureSkipVerify: true

        # Relabeling — add/modify labels before scraping
        relabelings:
        - sourceLabels: [__meta_kubernetes_pod_node_name]
          targetLabel: node

        # Metric relabeling — drop/modify metrics after scraping
        metricRelabelings:
        # Drop expensive histogram buckets to save storage
        - sourceLabels: [__name__]
          regex: '.*_bucket'
          action: drop
        # Rename a metric
        - sourceLabels: [__name__]
          regex: 'old_metric_name'
          replacement: 'new_metric_name'
          targetLabel: __name__
    ```

14. Create a PodMonitor (for pods without a Service):

    ```yaml
    apiVersion: monitoring.coreos.com/v1
    kind: PodMonitor
    metadata:
      name: sidecar-metrics
      namespace: default
      labels:
        release: prometheus-monitoring
    spec:
      selector:
        matchLabels:
          app: my-app
      podMetricsEndpoints:
      - port: metrics
        interval: 30s
        path: /metrics
    ```

## Architecture

```
Application (port 8080)
  ├── /healthz          → Health checks
  ├── /api/orders       → Business logic
  └── /metrics (or :9090/metrics) → Prometheus metrics endpoint
        ↓
ServiceMonitor (label: release=prometheus-monitoring)
        ↓
Prometheus Operator discovers target
        ↓
Prometheus scrapes /metrics every 15s
        ↓
PrometheusRules evaluate recording + alerting rules
        ↓
├── Recording rules → pre-computed metrics for dashboards
├── Alerting rules → fire alerts to Alertmanager
└── Grafana queries → real-time dashboards
```

## Key Concepts

- **ServiceMonitor**: CRD that declares how Prometheus should scrape a Kubernetes Service
- **PodMonitor**: Like ServiceMonitor but targets pods directly (no Service needed)
- **`release: prometheus-monitoring`**: The label Prometheus Operator uses to discover ServiceMonitors
- **Metric types**: Counter (always goes up), Gauge (goes up and down), Histogram (bucketed distribution), Summary (quantiles)
- **`/metrics` endpoint**: Standard Prometheus exposition format — text-based, human-readable
- **Metric relabeling**: Drop, rename, or modify metrics during scraping to control cardinality
- **Recording rules**: Pre-compute expensive queries for dashboard performance
- **Instrumentation libraries**: `prometheus_client` (Python), `promhttp` (Go), `prom-client` (Node.js)

## Cleanup

```bash
kubectl delete -f monitoring/sample-app/ --recursive --context=dev
kubectl delete prometheusrule metrics-demo-rules -n monitoring --context=dev
```
