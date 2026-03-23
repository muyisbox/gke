# Task 9: Configure Alertmanager Notification Routing and Silences

**Level:** Advanced Operations

**Objective:** Configure Alertmanager with notification receivers (Slack, email, webhook), set up routing trees to send alerts to the right team based on severity and labels, create silences for maintenance windows, and implement inhibition rules to suppress dependent alerts.

## Context

The kube-prometheus-stack deploys Alertmanager with 2 replicas, but no notification receivers are configured by default. Alerts fire and show in the Alertmanager UI but don't reach anyone. In production, you need:
- Different channels for different severities (critical → PagerDuty, warning → Slack, info → email)
- Team-based routing (team=platform → #platform-alerts, team=app → #app-alerts)
- Maintenance silences during planned changes
- Inhibition rules so a node-down alert suppresses all pod alerts on that node

## Steps

### Part A: Understand Current Alertmanager Configuration

1. Access Alertmanager and review the default config:

   ```bash
   kubectl port-forward svc/prometheus-monitoring-kube-alertmanager -n monitoring 9093:9093 --context=dev
   ```

   Navigate to `http://localhost:9093/#/status` to see the running configuration.

2. View firing alerts:

   ```bash
   curl -s http://localhost:9093/api/v2/alerts | jq '[.[] | {alertname: .labels.alertname, severity: .labels.severity, state: .status.state}]'
   ```

3. Check the current AlertmanagerConfig CRDs (Prometheus Operator way):

   ```bash
   kubectl get alertmanagerconfigs -A --context=dev
   ```

### Part B: Configure Slack Notifications

4. Create a GCP secret for the Slack webhook URL:

   ```bash
   # Store the Slack webhook URL in Secret Manager
   echo -n "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" | \
     gcloud secrets create alertmanager-slack-webhook \
       --data-file=- \
       --project=cluster-dreams \
       --replication-policy="automatic"
   ```

5. Create an ExternalSecret to sync it into the cluster:

   ```yaml
   # monitoring/alertmanager-secrets.yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: alertmanager-slack-webhook
     namespace: monitoring
   spec:
     refreshInterval: 24h
     secretStoreRef:
       name: gcp-secret-manager
       kind: ClusterSecretStore
     target:
       name: alertmanager-slack-webhook
       creationPolicy: Owner
     data:
     - secretKey: webhook-url
       remoteRef:
         key: alertmanager-slack-webhook
   ```

6. Configure Alertmanager via the kube-prometheus-stack Helm values. Update `gke-applications/dev/prometheus.yaml`:

   ```yaml
   helm:
     values:
       alertmanager:
         alertmanagerSpec:
           replicas: 2
           storageSpec:
             volumeClaimTemplate:
               spec:
                 storageClassName: standard
                 resources:
                   requests:
                     storage: 5Gi
         config:
           global:
             resolve_timeout: 5m
             slack_api_url_file: /etc/alertmanager/secrets/alertmanager-slack-webhook/webhook-url
           route:
             receiver: default-slack
             group_by: ['alertname', 'namespace']
             group_wait: 30s
             group_interval: 5m
             repeat_interval: 4h
             routes:
             # Critical alerts — immediate notification
             - receiver: critical-slack
               match:
                 severity: critical
               group_wait: 10s
               repeat_interval: 1h
               continue: false

             # Warning alerts — standard channel
             - receiver: warning-slack
               match:
                 severity: warning
               group_wait: 1m
               repeat_interval: 4h

             # Watchdog heartbeat — suppress (it's always firing)
             - receiver: "null"
               match:
                 alertname: Watchdog

           receivers:
           - name: "null"
           - name: default-slack
             slack_configs:
             - channel: "#alerts-dev"
               send_resolved: true
               title: '{{ template "slack.title" . }}'
               text: '{{ template "slack.text" . }}'
               actions:
               - type: button
                 text: "View in Grafana"
                 url: "http://grafana.monitoring.svc:3000"
               - type: button
                 text: "Silence"
                 url: '{{ template "slack.silence_url" . }}'
           - name: critical-slack
             slack_configs:
             - channel: "#alerts-critical"
               send_resolved: true
               title: ':rotating_light: CRITICAL: {{ .GroupLabels.alertname }}'
               text: >-
                 *Alert:* {{ .GroupLabels.alertname }}
                 *Severity:* {{ .CommonLabels.severity }}
                 *Namespace:* {{ .CommonLabels.namespace }}
                 {{ range .Alerts }}
                 - {{ .Annotations.summary }}
                   {{ .Annotations.description }}
                 {{ end }}
           - name: warning-slack
             slack_configs:
             - channel: "#alerts-warning"
               send_resolved: true
               title: ':warning: {{ .GroupLabels.alertname }}'
               text: >-
                 {{ range .Alerts }}
                 - *{{ .Labels.alertname }}* in {{ .Labels.namespace }}
                   {{ .Annotations.summary }}
                 {{ end }}

           templates:
           - '/etc/alertmanager/config/*.tmpl'

         templateFiles:
           slack-templates.tmpl: |-
             {{ define "slack.title" }}
             [{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .GroupLabels.alertname }}
             {{ end }}

             {{ define "slack.text" }}
             {{ range .Alerts }}
             *Alert:* {{ .Labels.alertname }}
             *Severity:* {{ .Labels.severity }}
             *Description:* {{ .Annotations.description }}
             *Details:*
               {{ range .Labels.SortedPairs }} • *{{ .Name }}:* `{{ .Value }}`
               {{ end }}
             {{ end }}
             {{ end }}

             {{ define "slack.silence_url" }}
             http://alertmanager.monitoring.svc:9093/#/silences/new?filter=%7Balertname%3D%22{{ .GroupLabels.alertname }}%22%7D
             {{ end }}

         # Mount the Slack webhook secret
         secrets:
         - alertmanager-slack-webhook
   ```

7. Commit the change and let ArgoCD sync, or apply manually for testing:

   ```bash
   # After ArgoCD syncs, verify the config was loaded
   curl -s http://localhost:9093/api/v2/status | jq '.config.original'
   ```

### Part C: Team-Based Routing

8. Add team-based routing to direct alerts to different channels per team:

   ```yaml
   # Add to the routes section:
   routes:
   # Platform team alerts
   - receiver: platform-slack
     match:
       team: platform
     routes:
     - receiver: platform-critical
       match:
         severity: critical

   # Application team alerts
   - receiver: app-team-slack
     match:
       team: application
   ```

   This works because the PrometheusRules in Task 7 include `team: platform` labels on alerts.

9. Use AlertmanagerConfig CRDs for namespace-scoped configuration (teams manage their own routing):

   ```yaml
   # monitoring/alertmanager-config-appteam.yaml
   apiVersion: monitoring.coreos.com/v1alpha1
   kind: AlertmanagerConfig
   metadata:
     name: app-team-config
     namespace: bookinfo
     labels:
       release: prometheus-monitoring
   spec:
     route:
       receiver: app-team-webhook
       groupBy: ['alertname']
       matchers:
       - name: namespace
         value: bookinfo
     receivers:
     - name: app-team-webhook
       webhookConfigs:
       - url: http://webhook-receiver.bookinfo.svc:8080/alerts
         sendResolved: true
   ```

### Part D: Create Silences for Maintenance

10. Create a silence via the API for a planned maintenance window:

    ```bash
    # Silence all alerts in the monitoring namespace for 2 hours
    SILENCE_ID=$(curl -s -X POST http://localhost:9093/api/v2/silences \
      -H "Content-Type: application/json" \
      -d '{
        "matchers": [
          {
            "name": "namespace",
            "value": "monitoring",
            "isRegex": false,
            "isEqual": true
          }
        ],
        "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
        "endsAt": "'$(date -u -v+2H +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "+2 hours" +%Y-%m-%dT%H:%M:%S.000Z)'",
        "createdBy": "platform-admin",
        "comment": "Planned maintenance: upgrading Prometheus stack"
      }' | jq -r '.silenceID')

    echo "Created silence: $SILENCE_ID"
    ```

11. List active silences:

    ```bash
    curl -s http://localhost:9093/api/v2/silences | \
      jq '.[] | select(.status.state=="active") | {id: .id, matchers: .matchers, endsAt: .endsAt, comment: .comment}'
    ```

12. Expire a silence early:

    ```bash
    curl -s -X DELETE "http://localhost:9093/api/v2/silence/${SILENCE_ID}"
    ```

### Part E: Inhibition Rules

13. Add inhibition rules so that higher-severity alerts suppress lower ones for the same target:

    ```yaml
    # Add to alertmanager.config in prometheus.yaml:
    inhibit_rules:
    # If a critical alert fires, suppress warnings for the same alertname+namespace
    - source_matchers:
      - severity = critical
      target_matchers:
      - severity = warning
      equal: ['alertname', 'namespace']

    # If a node is down, suppress all pod alerts on that node
    - source_matchers:
      - alertname = NodeDown
      target_matchers:
      - severity =~ "warning|info"
      equal: ['node']

    # If the cluster is unreachable, suppress all namespace alerts
    - source_matchers:
      - alertname = KubeAPIDown
      target_matchers:
      - severity =~ ".*"
    ```

### Part F: Webhook Receiver for Custom Integrations

14. Deploy a simple webhook receiver to test alert delivery:

    ```yaml
    # monitoring/webhook-receiver.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: alert-webhook-receiver
      namespace: monitoring
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: alert-webhook
      template:
        metadata:
          labels:
            app: alert-webhook
        spec:
          containers:
          - name: webhook
            image: python:3.12-slim
            command:
            - python
            - -c
            - |
              from http.server import HTTPServer, BaseHTTPRequestHandler
              import json, sys

              class Handler(BaseHTTPRequestHandler):
                  def do_POST(self):
                      content_length = int(self.headers['Content-Length'])
                      body = self.rfile.read(content_length)
                      alerts = json.loads(body)
                      for alert in alerts.get('alerts', []):
                          status = alert['status']
                          name = alert['labels'].get('alertname', 'unknown')
                          severity = alert['labels'].get('severity', 'unknown')
                          print(f"[{status.upper()}] {name} (severity={severity})", flush=True)
                      self.send_response(200)
                      self.end_headers()

              print("Webhook receiver listening on :8080", flush=True)
              HTTPServer(('', 8080), Handler).serve_forever()
            ports:
            - containerPort: 8080
            resources:
              requests:
                cpu: 10m
                memory: 32Mi
              limits:
                memory: 64Mi
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: alert-webhook-receiver
      namespace: monitoring
    spec:
      selector:
        app: alert-webhook
      ports:
      - port: 8080
        targetPort: 8080
    ```

15. Add a webhook receiver to Alertmanager config:

    ```yaml
    receivers:
    - name: webhook-debug
      webhook_configs:
      - url: http://alert-webhook-receiver.monitoring.svc:8080/alerts
        send_resolved: true
    ```

16. Trigger an alert and verify delivery:

    ```bash
    # Deploy the webhook receiver
    kubectl apply -f monitoring/webhook-receiver.yaml --context=dev

    # Create a test pod that will crash
    kubectl run alert-test --image=busybox -n default --context=dev -- /bin/sh -c "exit 1"

    # Watch the webhook receiver logs for alerts
    kubectl logs -f -l app=alert-webhook -n monitoring --context=dev
    ```

### Part G: Verify End-to-End

17. Complete verification checklist:

    ```bash
    # 1. Check Alertmanager is healthy
    curl -s http://localhost:9093/api/v2/status | jq '.cluster.status'

    # 2. Check receivers are configured
    curl -s http://localhost:9093/api/v2/status | jq '.config.original' | grep -c "receiver:"

    # 3. Count active alerts
    curl -s http://localhost:9093/api/v2/alerts | jq '[.[] | select(.status.state=="active")] | length'

    # 4. Check silences
    curl -s http://localhost:9093/api/v2/silences | jq '[.[] | select(.status.state=="active")] | length'

    # 5. Verify Alertmanager cluster peers (should be 2)
    curl -s http://localhost:9093/api/v2/status | jq '.cluster.peers | length'
    ```

## Key Concepts

- **Routing tree**: Alerts traverse routes top-to-bottom; first matching route wins (unless `continue: true`)
- **Group by**: Alerts with the same `group_by` labels are batched into a single notification
- **Group wait**: How long to buffer alerts before sending the first notification for a group
- **Repeat interval**: How often to re-send a notification for the same group of firing alerts
- **Silences**: Temporarily suppress notifications (alerts still fire, just not notified)
- **Inhibition**: Automatically suppress alerts when a related higher-severity alert is firing
- **AlertmanagerConfig CRD**: Namespace-scoped configuration (teams manage their own routing)
- **Webhook receivers**: Generic HTTP endpoint for custom integrations (Jira, Teams, custom systems)
- **`send_resolved: true`**: Send a notification when the alert resolves (green message)

## Cleanup

```bash
kubectl delete -f monitoring/webhook-receiver.yaml --context=dev
kubectl delete -f monitoring/alertmanager-secrets.yaml --context=dev
kubectl delete pod alert-test -n default --context=dev --ignore-not-found
```
