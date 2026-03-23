# Task 7: Write and Deploy Custom PrometheusRules for Application Alerting

**Level:** Advanced Operations

**Objective:** Create custom PrometheusRules with recording rules and alerting rules, deploy them via the GitOps pipeline, verify they're picked up by Prometheus, and test alert firing through simulated failure scenarios.

## Context

The kube-prometheus-stack deployed on this platform (v82.10.3) comes with a large set of built-in alerting rules for infrastructure (node, kubelet, API server, etcd). However, platform teams need custom rules for:
- Application-level SLIs (error rate, latency, availability)
- Business-critical thresholds (queue depth, request budget burn rate)
- Recording rules that pre-compute expensive queries for dashboards

PrometheusRules are CRDs managed by the Prometheus Operator. The operator watches for PrometheusRule resources with the label `release: prometheus-monitoring` and automatically reloads Prometheus configuration.

## Steps

### Part A: Understand Existing Rules

1. Explore the built-in PrometheusRules shipped with kube-prometheus-stack:

   ```bash
   # List all PrometheusRule resources
   kubectl get prometheusrules -n monitoring --context=dev

   # Count the number of rules
   kubectl get prometheusrules -n monitoring --context=dev --no-headers | wc -l

   # Examine a specific rule group
   kubectl get prometheusrule prometheus-monitoring-kube-prometheus-kubernetes-system -n monitoring --context=dev -o yaml
   ```

2. Understand the rule format by inspecting an existing rule:

   ```bash
   kubectl get prometheusrule prometheus-monitoring-kube-prometheus-general.rules -n monitoring --context=dev -o yaml | head -60
   ```

   Key fields:
   - `spec.groups[].name` — Group name (organizes related rules)
   - `spec.groups[].rules[].record` — Recording rule (pre-computed metric)
   - `spec.groups[].rules[].alert` — Alert rule (fires when condition met)
   - `spec.groups[].rules[].expr` — PromQL expression
   - `spec.groups[].rules[].for` — Duration the condition must hold before firing
   - `spec.groups[].rules[].labels.severity` — Alert severity (critical, warning, info)
   - `spec.groups[].rules[].annotations` — Human-readable descriptions

3. Verify which label selector Prometheus uses to discover rules:

   ```bash
   kubectl get prometheus -n monitoring --context=dev -o yaml | grep -A5 ruleSelector
   ```

   You should see it matches `release: prometheus-monitoring`.

### Part B: Create Recording Rules

Recording rules pre-compute frequently-used or expensive PromQL queries and store the result as a new time series. This makes dashboards faster and reduces Prometheus query load.

4. Create recording rules for HTTP request rate metrics:

   ```yaml
   # monitoring/recording-rules.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: application-recording-rules
     namespace: monitoring
     labels:
       release: prometheus-monitoring
       app.kubernetes.io/part-of: platform-monitoring
   spec:
     groups:
     - name: http_request_rates
       interval: 30s
       rules:
       # Total request rate per service (5m window)
       - record: service:http_requests:rate5m
         expr: |
           sum(rate(istio_requests_total[5m])) by (destination_service_name, destination_service_namespace)

       # Error rate per service (5xx responses)
       - record: service:http_errors:rate5m
         expr: |
           sum(rate(istio_requests_total{response_code=~"5.."}[5m])) by (destination_service_name, destination_service_namespace)

       # Error ratio (errors / total)
       - record: service:http_error_ratio:rate5m
         expr: |
           service:http_errors:rate5m / service:http_requests:rate5m

       # P99 latency per service
       - record: service:http_request_duration_seconds:p99
         expr: |
           histogram_quantile(0.99,
             sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (destination_service_name, le)
           ) / 1000

       # P95 latency per service
       - record: service:http_request_duration_seconds:p95
         expr: |
           histogram_quantile(0.95,
             sum(rate(istio_request_duration_milliseconds_bucket[5m])) by (destination_service_name, le)
           ) / 1000

     - name: resource_utilization
       interval: 60s
       rules:
       # CPU utilization ratio (used / requested)
       - record: namespace:container_cpu_utilization:ratio
         expr: |
           sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)
           /
           sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)

       # Memory utilization ratio (used / requested)
       - record: namespace:container_memory_utilization:ratio
         expr: |
           sum(container_memory_working_set_bytes{container!=""}) by (namespace)
           /
           sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace)

       # Pod restart rate per namespace (1h window)
       - record: namespace:pod_restarts:rate1h
         expr: |
           sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace)
   ```

5. Apply and verify the recording rules are loaded:

   ```bash
   kubectl apply -f monitoring/recording-rules.yaml --context=dev

   # Verify the PrometheusRule is picked up
   kubectl get prometheusrule application-recording-rules -n monitoring --context=dev

   # Wait 30 seconds, then query the new metric in Prometheus
   kubectl port-forward svc/prometheus-monitoring-kube-prometheus -n monitoring 9090:9090 --context=dev

   # In another terminal, query the recording rule
   curl -s 'http://localhost:9090/api/v1/query?query=service:http_requests:rate5m' | jq '.data.result[:3]'
   ```

### Part C: Create Alerting Rules

6. Create alerting rules for application health:

   ```yaml
   # monitoring/alerting-rules.yaml
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: application-alerting-rules
     namespace: monitoring
     labels:
       release: prometheus-monitoring
       app.kubernetes.io/part-of: platform-monitoring
   spec:
     groups:
     - name: application_availability
       rules:
       # High error rate alert
       - alert: HighErrorRate
         expr: |
           (
             sum(rate(istio_requests_total{response_code=~"5..", reporter="destination"}[5m])) by (destination_service_name, destination_service_namespace)
             /
             sum(rate(istio_requests_total{reporter="destination"}[5m])) by (destination_service_name, destination_service_namespace)
           ) > 0.05
         for: 5m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "High error rate on {{ $labels.destination_service_name }}"
           description: >-
             Service {{ $labels.destination_service_name }} in namespace
             {{ $labels.destination_service_namespace }} has an error rate
             above 5% (current: {{ $value | humanizePercentage }}).
           runbook_url: "https://runbooks.example.com/high-error-rate"

       # Critical error rate (>20%)
       - alert: CriticalErrorRate
         expr: |
           (
             sum(rate(istio_requests_total{response_code=~"5..", reporter="destination"}[5m])) by (destination_service_name, destination_service_namespace)
             /
             sum(rate(istio_requests_total{reporter="destination"}[5m])) by (destination_service_name, destination_service_namespace)
           ) > 0.20
         for: 2m
         labels:
           severity: critical
           team: platform
         annotations:
           summary: "CRITICAL error rate on {{ $labels.destination_service_name }}"
           description: >-
             Service {{ $labels.destination_service_name }} in namespace
             {{ $labels.destination_service_namespace }} has an error rate
             above 20% (current: {{ $value | humanizePercentage }}).
             Immediate investigation required.

     - name: pod_health
       rules:
       # Pod CrashLooping
       - alert: PodCrashLooping
         expr: |
           increase(kube_pod_container_status_restarts_total[1h]) > 5
         for: 10m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "Pod {{ $labels.pod }} is crash-looping"
           description: >-
             Pod {{ $labels.pod }} in namespace {{ $labels.namespace }}
             has restarted {{ $value | humanize }} times in the last hour.

       # Pod stuck in Pending
       - alert: PodStuckPending
         expr: |
           kube_pod_status_phase{phase="Pending"} == 1
         for: 15m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "Pod {{ $labels.pod }} stuck in Pending"
           description: >-
             Pod {{ $labels.pod }} in namespace {{ $labels.namespace }}
             has been in Pending state for more than 15 minutes.
             Check resource quotas, node capacity, or taints/tolerations.

       # Container OOMKilled
       - alert: ContainerOOMKilled
         expr: |
           kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
         for: 0m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "Container {{ $labels.container }} OOMKilled"
           description: >-
             Container {{ $labels.container }} in pod {{ $labels.pod }}
             (namespace: {{ $labels.namespace }}) was OOMKilled.
             Consider increasing memory limits.

     - name: resource_pressure
       rules:
       # Namespace approaching CPU quota
       - alert: NamespaceCPUQuotaNearLimit
         expr: |
           (
             sum(kube_resourcequota{type="used", resource="requests.cpu"}) by (namespace)
             /
             sum(kube_resourcequota{type="hard", resource="requests.cpu"}) by (namespace)
           ) > 0.85
         for: 10m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "Namespace {{ $labels.namespace }} CPU quota at {{ $value | humanizePercentage }}"
           description: >-
             Namespace {{ $labels.namespace }} is using more than 85% of its
             CPU request quota. New deployments may fail.

       # PVC usage high
       - alert: PVCUsageHigh
         expr: |
           (
             kubelet_volume_stats_used_bytes
             /
             kubelet_volume_stats_capacity_bytes
           ) > 0.85
         for: 15m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "PVC {{ $labels.persistentvolumeclaim }} usage above 85%"
           description: >-
             PVC {{ $labels.persistentvolumeclaim }} in namespace
             {{ $labels.namespace }} is at {{ $value | humanizePercentage }}
             capacity. Consider expanding the volume.

     - name: certificate_health
       rules:
       # Certificate expiring soon
       - alert: CertificateExpiringSoon
         expr: |
           (certmanager_certificate_expiration_timestamp_seconds - time()) / 86400 < 14
         for: 1h
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "Certificate {{ $labels.name }} expires in {{ $value | humanize }} days"
           description: >-
             Certificate {{ $labels.name }} in namespace {{ $labels.namespace }}
             will expire in less than 14 days. Check cert-manager logs for renewal failures.

       # Certificate not ready
       - alert: CertificateNotReady
         expr: |
           certmanager_certificate_ready_status{condition="True"} != 1
         for: 30m
         labels:
           severity: warning
           team: platform
         annotations:
           summary: "Certificate {{ $labels.name }} is not ready"
           description: >-
             Certificate {{ $labels.name }} in namespace {{ $labels.namespace }}
             has not been ready for 30 minutes. Investigate cert-manager.
   ```

7. Apply and verify:

   ```bash
   kubectl apply -f monitoring/alerting-rules.yaml --context=dev

   # Check the rules are loaded
   kubectl get prometheusrule application-alerting-rules -n monitoring --context=dev

   # Check for any configuration errors in Prometheus
   kubectl logs -l app.kubernetes.io/name=prometheus -n monitoring --context=dev --tail=20 | grep -i "error\|rule"

   # View active rules in the Prometheus UI
   # Navigate to http://localhost:9090/rules (with port-forward active)
   ```

### Part D: Test Alert Firing

8. Simulate a CrashLooping pod to trigger the `PodCrashLooping` alert:

   ```bash
   # Deploy a pod that will crash repeatedly
   kubectl run crash-test --image=busybox -n default --context=dev \
     --restart=Always -- /bin/sh -c "exit 1"

   # Watch the restarts increase
   kubectl get pod crash-test -n default --context=dev -w

   # After ~10 minutes, check Alertmanager for the firing alert
   kubectl port-forward svc/prometheus-monitoring-kube-alertmanager -n monitoring 9093:9093 --context=dev

   # In another terminal:
   curl -s http://localhost:9093/api/v2/alerts | jq '.[].labels.alertname'
   ```

9. Verify in the Prometheus UI:

   ```bash
   # With Prometheus port-forwarded on 9090:
   # Go to http://localhost:9090/alerts
   # Find "PodCrashLooping" — it should show as PENDING then FIRING
   ```

10. Clean up the test:

    ```bash
    kubectl delete pod crash-test -n default --context=dev
    ```

### Part E: Deploy Rules via GitOps

11. Instead of `kubectl apply`, deploy PrometheusRules through the ArgoCD pipeline. Create a new app definition:

    ```yaml
    # gke-applications/dev/platform-alerting-rules.yaml
    name: platform-alerting-rules
    chart: raw
    repoURL: https://charts.helm.sh/incubator
    targetRevision: "0.2.5"
    namespace: monitoring
    cluster_env: dev
    helm:
      values:
        resources:
        - apiVersion: monitoring.coreos.com/v1
          kind: PrometheusRule
          metadata:
            name: application-recording-rules
            labels:
              release: prometheus-monitoring
          spec:
            groups:
            - name: http_request_rates
              interval: 30s
              rules:
              - record: service:http_requests:rate5m
                expr: |
                  sum(rate(istio_requests_total[5m])) by (destination_service_name, destination_service_namespace)
              - record: service:http_errors:rate5m
                expr: |
                  sum(rate(istio_requests_total{response_code=~"5.."}[5m])) by (destination_service_name, destination_service_namespace)
        - apiVersion: monitoring.coreos.com/v1
          kind: PrometheusRule
          metadata:
            name: application-alerting-rules
            labels:
              release: prometheus-monitoring
          spec:
            groups:
            - name: application_availability
              rules:
              - alert: HighErrorRate
                expr: |
                  (
                    sum(rate(istio_requests_total{response_code=~"5..", reporter="destination"}[5m])) by (destination_service_name, destination_service_namespace)
                    /
                    sum(rate(istio_requests_total{reporter="destination"}[5m])) by (destination_service_name, destination_service_namespace)
                  ) > 0.05
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "High error rate on {{ $labels.destination_service_name }}"
    ```

    Alternatively, create a custom Helm chart for your rules (see Task 3 for OCI chart creation).

### Part F: SDLC Promotion

12. After validating rules in dev, promote to staging and gitops:

    - Copy the app definition to `gke-applications/staging/` and `gke-applications/gitops/`
    - Change `cluster_env` accordingly
    - Consider adjusting thresholds per environment:
      - **dev**: Higher thresholds (more tolerance), shorter `for` durations for faster testing
      - **staging**: Production-like thresholds
      - **gitops**: Production thresholds with longer `for` durations to reduce noise

13. Verify rules are consistent across environments:

    ```bash
    for ctx in dev staging gitops; do
      echo "=== $ctx ==="
      kubectl get prometheusrules -n monitoring --context=$ctx --no-headers | wc -l
    done
    ```

## Key Concepts

- **Recording rules**: Pre-compute metrics for faster dashboard queries; use `record:` field
- **Alerting rules**: Fire alerts when PromQL conditions hold for a duration; use `alert:` field
- **`for` duration**: Prevents flapping — condition must be true for this long before firing
- **Severity labels**: `critical` (page), `warning` (ticket), `info` (dashboard only)
- **Annotations**: Human-readable text with template variables (`{{ $labels.pod }}`, `{{ $value }}`)
- **Label matching**: Prometheus Operator discovers rules via `release: prometheus-monitoring` label
- **Rule groups**: Related rules grouped together; evaluated at the group's `interval`
- **Runbook URLs**: Link to remediation procedures in annotations

## Cleanup

```bash
kubectl delete prometheusrule application-recording-rules application-alerting-rules -n monitoring --context=dev
kubectl delete pod crash-test -n default --context=dev --ignore-not-found
```
