# Task 11: Troubleshoot Monitoring Stack Failures — High Cardinality, Scrape Issues, and Storage Pressure

**Level:** Advanced Operations

**Objective:** Diagnose and resolve common Prometheus monitoring stack failures: high cardinality metric explosion causing OOM, scrape target failures, disk pressure on persistent volumes, Grafana dashboard loading issues, and Alertmanager clustering problems.

## Context

The monitoring stack (kube-prometheus-stack v82.10.3) is itself critical infrastructure. When monitoring breaks, you lose visibility into everything else. This task covers the most common production failures and how to systematically diagnose and fix them.

## Scenario

You've received multiple reports:
- Prometheus pods are OOMKilled and restarting
- Some ServiceMonitor targets show as DOWN
- Grafana dashboards are slow to load or timing out
- Alertmanager silences aren't propagating between replicas

## Steps

### Part A: Prometheus OOMKilled — High Cardinality Investigation

1. Check if Prometheus pods are being OOMKilled:

   ```bash
   kubectl get pods -n monitoring --context=dev -l app.kubernetes.io/name=prometheus

   # Check for OOMKilled in recent events
   kubectl get events -n monitoring --context=dev --sort-by='.lastTimestamp' | grep -i oom

   # Check container's last termination reason
   kubectl get pod -n monitoring --context=dev -l app.kubernetes.io/name=prometheus \
     -o jsonpath='{range .items[*]}{.metadata.name}: {.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'
   ```

2. Identify high-cardinality metrics (the #1 cause of Prometheus OOM):

   ```bash
   # Port-forward to Prometheus
   kubectl port-forward svc/prometheus-monitoring-kube-prometheus -n monitoring 9090:9090 --context=dev

   # Find the top 20 metrics by number of time series
   curl -s http://localhost:9090/api/v1/status/tsdb | jq '.data.seriesCountByMetricName[:20]'

   # Check total active time series
   curl -s http://localhost:9090/api/v1/status/tsdb | jq '.data.headStats'

   # Find metrics with the most label combinations
   curl -s 'http://localhost:9090/api/v1/query?query=topk(10, count by (__name__)({__name__=~".+"}))' | \
     jq '.data.result[] | {metric: .metric.__name__, series_count: .value[1]}'
   ```

3. Identify which labels are causing cardinality explosion:

   ```bash
   # Check if a specific metric has too many unique label values
   # Common offenders: le (histogram buckets), path/url (high cardinality), pod (ephemeral)
   curl -s 'http://localhost:9090/api/v1/query?query=count(istio_requests_total) by (response_code, source_workload, destination_workload)' | \
     jq '.data.result | length'

   # Check for unbounded labels (e.g., user IDs, request IDs in labels)
   curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data | length'
   ```

4. Fix high cardinality with metric relabeling. Add to the ServiceMonitor or Prometheus config:

   ```yaml
   # Option 1: Drop specific high-cardinality metrics in ServiceMonitor
   metricRelabelings:
   - sourceLabels: [__name__]
     regex: 'go_gc_.*|go_memstats_.*'
     action: drop

   # Option 2: Drop high-cardinality labels
   metricRelabelings:
   - regex: 'pod_template_hash'
     action: labeldrop

   # Option 3: Set in Prometheus spec for global metric limits
   # In prometheus.yaml helm values:
   prometheus:
     prometheusSpec:
       enforcedSampleLimit: 50000      # Max samples per scrape
       enforcedLabelLimit: 30          # Max labels per sample
       enforcedLabelNameLengthLimit: 200
       enforcedLabelValueLengthLimit: 500
   ```

5. Increase Prometheus memory if cardinality is expected:

   ```yaml
   # In prometheus.yaml helm values:
   prometheus:
     prometheusSpec:
       resources:
         requests:
           cpu: 500m
           memory: 2Gi
         limits:
           memory: 4Gi
   ```

### Part B: Scrape Target Failures

6. Check which scrape targets are unhealthy:

   ```bash
   # List all targets and their health
   curl -s http://localhost:9090/api/v1/targets | \
     jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, instance: .labels.instance, health: .health, lastError: .lastError}'

   # Count healthy vs unhealthy targets
   curl -s http://localhost:9090/api/v1/targets | \
     jq '{
       up: [.data.activeTargets[] | select(.health == "up")] | length,
       down: [.data.activeTargets[] | select(.health != "up")] | length
     }'
   ```

7. Common scrape failure causes and fixes:

   ```bash
   # Cause 1: Service/pod is down
   # Check if the target pods are running
   kubectl get pods -n default --context=dev -l app=metrics-demo

   # Cause 2: Wrong port in ServiceMonitor
   # Verify the port name matches the Service definition
   kubectl get svc metrics-demo -n default --context=dev -o yaml | grep -A5 ports

   # Cause 3: Network policy blocking Prometheus
   # Check if NetworkPolicies exist that block monitoring namespace
   kubectl get networkpolicies -A --context=dev

   # Cause 4: Istio mTLS blocking non-mesh scraping
   # Check if the scrape target needs Istio STRICT mTLS exception
   kubectl get peerauthentication -A --context=dev

   # Fix: Add Prometheus scraping annotation to bypass Istio mTLS
   # In the ServiceMonitor:
   #   endpoints:
   #   - port: metrics
   #     scheme: https
   #     tlsConfig:
   #       insecureSkipVerify: true
   #       caFile: /etc/prometheus/certs/ca.crt
   ```

8. Check dropped targets (ServiceMonitors that Prometheus isn't picking up):

   ```bash
   # List all ServiceMonitors
   kubectl get servicemonitors -A --context=dev

   # Check the Prometheus Operator logs for discovery issues
   kubectl logs -l app.kubernetes.io/name=prometheus-operator -n monitoring --context=dev --tail=50 | grep -i "error\|warning"

   # Verify the ServiceMonitor label matches what Prometheus expects
   kubectl get prometheus -n monitoring --context=dev -o yaml | grep -A10 serviceMonitorSelector
   ```

### Part C: Storage Pressure — PVC Full

9. Check Prometheus storage usage:

   ```bash
   # Check PVC usage
   kubectl exec -n monitoring --context=dev \
     $(kubectl get pod -n monitoring --context=dev -l app.kubernetes.io/name=prometheus -o name | head -1) \
     -- df -h /prometheus

   # Check TSDB stats
   curl -s http://localhost:9090/api/v1/status/tsdb | jq '{
     numSeries: .data.headStats.numSeries,
     numChunks: .data.headStats.numChunks,
     minTime: .data.headStats.minTime,
     maxTime: .data.headStats.maxTime
   }'

   # Check data retention
   curl -s http://localhost:9090/api/v1/status/runtimeinfo | jq '{
     storageRetention: .data.storageRetention,
     WALSize: .data.WALSize
   }'
   ```

10. Fix storage pressure:

    ```yaml
    # Option 1: Increase PVC size (if storage class supports expansion)
    prometheus:
      prometheusSpec:
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: standard
              resources:
                requests:
                  storage: 20Gi  # Was 10Gi

    # Option 2: Reduce retention
    prometheus:
      prometheusSpec:
        retention: 7d           # Default is 10d
        retentionSize: "8GB"    # Delete oldest data when hitting this limit

    # Option 3: Use retention size-based policy
    prometheus:
      prometheusSpec:
        retentionSize: "9GB"    # Keep 90% of disk for safety
    ```

11. Manually trigger a TSDB compaction:

    ```bash
    # Trigger compaction via the admin API (must be enabled)
    curl -s -X POST http://localhost:9090/api/v1/admin/tsdb/clean_tombstones
    ```

### Part D: Grafana Dashboard Issues

12. Diagnose slow dashboard loading:

    ```bash
    # Port-forward to Grafana
    kubectl port-forward svc/prometheus-monitoring-grafana -n monitoring 3000:80 --context=dev

    # Check Grafana's health
    curl -s -u admin:prom-operator http://localhost:3000/api/health

    # Check datasource connectivity
    curl -s -u admin:prom-operator http://localhost:3000/api/datasources | jq '.[].name'

    # Test Prometheus datasource
    curl -s -u admin:prom-operator http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up | jq '.status'
    ```

13. Common Grafana issues and fixes:

    ```bash
    # Issue: Dashboard ConfigMap not loaded
    # Check the sidecar is running
    kubectl get pod -n monitoring --context=dev -l app.kubernetes.io/name=grafana -o yaml | \
      grep -A5 "sidecar"

    # Issue: Missing dashboards after restart
    # Verify ConfigMaps have the correct label
    kubectl get configmaps -n monitoring --context=dev -l grafana_dashboard=1

    # Issue: Datasource connection refused
    # Check if Prometheus service is accessible from Grafana pod
    kubectl exec -n monitoring --context=dev \
      $(kubectl get pod -n monitoring --context=dev -l app.kubernetes.io/name=grafana -o name | head -1) \
      -c grafana -- wget -qO- http://prometheus-monitoring-kube-prometheus.monitoring:9090/api/v1/query?query=up 2>&1 | head -5
    ```

### Part E: Alertmanager Clustering Issues

14. Check Alertmanager cluster health:

    ```bash
    # Port-forward to Alertmanager
    kubectl port-forward svc/prometheus-monitoring-kube-alertmanager -n monitoring 9093:9093 --context=dev

    # Check cluster status — should show 2 peers
    curl -s http://localhost:9093/api/v2/status | jq '{
      cluster_status: .cluster.status,
      peer_count: (.cluster.peers | length),
      peers: [.cluster.peers[].address]
    }'
    ```

15. Fix common clustering issues:

    ```bash
    # Issue: Peers not discovering each other
    # Check Alertmanager pods can resolve each other
    kubectl exec -n monitoring --context=dev \
      $(kubectl get pod -n monitoring --context=dev -l app.kubernetes.io/name=alertmanager -o name | head -1) \
      -- wget -qO- http://prometheus-monitoring-kube-alertmanager-0.prometheus-monitoring-kube-alertmanager.monitoring:9093/api/v2/status 2>&1 | head -1

    # Issue: Silences not syncing between replicas
    # Silences replicate via the mesh protocol on port 9094
    # Check if the mesh port is accessible
    kubectl get svc prometheus-monitoring-kube-alertmanager -n monitoring --context=dev -o yaml | grep 9094
    ```

### Part F: Monitoring Stack Health Dashboard

16. Create a "meta-monitoring" dashboard that monitors the monitoring stack itself:

    ```promql
    # Prometheus scrape duration (should be < scrape_interval)
    scrape_duration_seconds{job="prometheus"}

    # Prometheus TSDB head series (watch for sudden spikes = cardinality explosion)
    prometheus_tsdb_head_series

    # Prometheus WAL corruption count (should be 0)
    prometheus_tsdb_wal_corruptions_total

    # Prometheus rule evaluation failures (should be 0)
    prometheus_rule_evaluation_failures_total

    # Alertmanager notification failures
    alertmanager_notifications_failed_total

    # Alertmanager silences active
    alertmanager_silences{state="active"}

    # Grafana active users
    grafana_stat_active_users
    ```

17. Create PrometheusRules for monitoring the monitoring stack:

    ```yaml
    # monitoring/meta-monitoring-rules.yaml
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: meta-monitoring-rules
      namespace: monitoring
      labels:
        release: prometheus-monitoring
    spec:
      groups:
      - name: meta_monitoring
        rules:
        - alert: PrometheusHighCardinality
          expr: prometheus_tsdb_head_series > 500000
          for: 15m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Prometheus has {{ $value }} active time series"
            description: >-
              Prometheus on {{ $labels.instance }} has more than 500k active
              time series. Investigate high-cardinality metrics to prevent OOM.

        - alert: PrometheusScrapeFailures
          expr: |
            sum(up == 0) > 3
          for: 10m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "{{ $value }} Prometheus scrape targets are down"

        - alert: PrometheusStorageFull
          expr: |
            (
              prometheus_tsdb_storage_blocks_bytes
              /
              (1024 * 1024 * 1024 * 10)
            ) > 0.85
          for: 15m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Prometheus storage is above 85% capacity"

        - alert: AlertmanagerClusterDegraded
          expr: |
            alertmanager_cluster_members < 2
          for: 5m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Alertmanager cluster has only {{ $value }} member(s)"
            description: >-
              Expected 2 Alertmanager peers but only {{ $value }} are in the
              cluster. Silences and notifications may not be consistent.
    ```

### Part G: Recovery Procedures

18. Emergency recovery steps for common scenarios:

    ```bash
    # Scenario 1: Prometheus OOMKilled repeatedly
    # Scale down to 1 replica to reduce load, then fix cardinality
    kubectl scale statefulset -n monitoring --context=dev \
      $(kubectl get statefulset -n monitoring --context=dev -l app.kubernetes.io/name=prometheus -o name) \
      --replicas=1

    # Scenario 2: Prometheus PVC full — delete old data
    # Reduce retention temporarily
    # Update prometheus.yaml: retention: 3d, then sync via ArgoCD

    # Scenario 3: All monitoring pods down — restart in order
    # 1. Prometheus Operator first
    kubectl rollout restart deployment prometheus-monitoring-kube-prometheus-operator -n monitoring --context=dev
    kubectl rollout status deployment prometheus-monitoring-kube-prometheus-operator -n monitoring --context=dev

    # 2. Then Prometheus
    kubectl rollout restart statefulset prometheus-prometheus-monitoring-kube-prometheus -n monitoring --context=dev

    # 3. Then Alertmanager
    kubectl rollout restart statefulset alertmanager-prometheus-monitoring-kube-alertmanager -n monitoring --context=dev

    # 4. Then Grafana
    kubectl rollout restart deployment prometheus-monitoring-grafana -n monitoring --context=dev
    ```

## Key Concepts

- **Cardinality**: The total number of unique time series. High cardinality (>1M series) causes OOM
- **Metric relabeling**: Drop or modify metrics during scraping to control cardinality
- **enforcedSampleLimit**: Per-scrape limit that prevents a single target from overwhelming Prometheus
- **TSDB compaction**: Prometheus periodically merges blocks; can be triggered manually
- **retentionSize**: Size-based retention ensures Prometheus never fills the disk
- **Meta-monitoring**: Monitoring the monitoring stack itself with dedicated alerts
- **Alertmanager mesh**: Replicas communicate on port 9094 to synchronize silences and deduplication
- **Grafana sidecar**: Watches ConfigMaps for dashboards; restart sidecar if dashboards disappear

## Cleanup

```bash
kubectl delete prometheusrule meta-monitoring-rules -n monitoring --context=dev
```
