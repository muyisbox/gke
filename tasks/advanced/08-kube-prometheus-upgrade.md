# Task 8: Upgrade kube-prometheus-stack with CRD Handling

**Level:** Advanced

**Objective:** Upgrade the kube-prometheus-stack across all clusters, handling CRD updates, Prometheus data migration, and Grafana dashboard compatibility.

## Context

The monitoring stack (chart v82.10.3) deploys Prometheus, Alertmanager, Grafana, and dozens of CRDs (PrometheusRule, ServiceMonitor, PodMonitor, etc.). Major version upgrades often include CRD changes that require careful handling.

## Steps

### Part A: Pre-Upgrade Assessment

1. Document current versions:

   ```bash
   kubectl get pods -n monitoring -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image
   ```

2. List all monitoring CRDs:

   ```bash
   kubectl get crds | grep monitoring.coreos.com
   ```

3. Count resources using these CRDs:

   ```bash
   kubectl get servicemonitors -A --no-headers | wc -l
   kubectl get prometheusrules -A --no-headers | wc -l
   kubectl get podmonitors -A --no-headers | wc -l
   ```

4. Check persistent data:

   ```bash
   kubectl get pvc -n monitoring
   ```

   Current config (`gke-applications/dev/prometheus-monitoring.yaml`):
   - Prometheus: 2 replicas, 10Gi storage
   - Alertmanager: 2 replicas, 5Gi storage

### Part B: Check for Breaking Changes

5. Before any upgrade, check the Helm chart changelog:

   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   helm search repo prometheus-community/kube-prometheus-stack --versions | head -20
   ```

6. Common breaking changes in major versions:
   - CRD API version changes (v1alpha1 → v1)
   - Renamed Helm values
   - Removed default ServiceMonitors
   - Grafana dashboard format changes

### Part C: Upgrade CRDs Manually (Required)

7. Helm does NOT update CRDs automatically. You must apply them manually before upgrading:

   ```bash
   # Get the target version's CRDs
   helm pull prometheus-community/kube-prometheus-stack --version <target-version> --untar
   kubectl apply --server-side -f kube-prometheus-stack/charts/crds/crds/ 2>/dev/null || \
   kubectl apply --server-side -f kube-prometheus-stack/crds/
   ```

8. Verify CRDs are updated:

   ```bash
   kubectl get crd prometheuses.monitoring.coreos.com -o jsonpath='{.spec.versions[*].name}'
   ```

### Part D: Upgrade Dev First

9. Create a branch:

   ```bash
   git checkout -b upgrade/prometheus-stack
   ```

10. Update `gke-applications/dev/prometheus-monitoring.yaml`:
    - Change `targetRevision` to the new version
    - Review and update any changed Helm values

11. Commit, push, PR. Review the ArgoCD diff before merge:

    ```bash
    # In ArgoCD UI: check the diff for the dev prometheus-monitoring application
    # Look for:
    # - Changed resource specs
    # - New/removed resources
    # - CRD version changes
    ```

12. After merge, watch the upgrade:

    ```bash
    kubectl get pods -n monitoring -w --context=dev
    ```

### Part E: Validate the Upgrade

13. Check all monitoring components:

    ```bash
    kubectl get pods -n monitoring
    kubectl get statefulsets -n monitoring
    ```

14. Verify Prometheus is scraping:

    ```bash
    kubectl port-forward svc/prometheus-monitoring-kube-prometheus -n monitoring 9090:9090
    # Run query: up
    # Should show all targets
    ```

15. Verify Grafana dashboards work:

    ```bash
    kubectl port-forward svc/prometheus-monitoring-grafana -n monitoring 3000:80
    ```

16. Verify ServiceMonitors from other apps still work:

    ```bash
    kubectl get servicemonitors -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,RELEASE:.metadata.labels.release
    ```

    All ServiceMonitors should have `release: prometheus-monitoring`.

17. Check Alertmanager:

    ```bash
    kubectl port-forward svc/prometheus-monitoring-kube-alertmanager -n monitoring 9093:9093
    ```

### Part F: Promote to Staging and Gitops

18. After validating dev, update staging and gitops files.

19. **Important for gitops cluster**: The gitops cluster runs ArgoCD. If the monitoring upgrade breaks something, you need to be able to recover without ArgoCD. Plan accordingly.

### Part G: Handle PVC Resize (If Needed)

20. If Prometheus storage needs increasing:

    ```yaml
    prometheus:
      prometheusSpec:
        storageSpec:
          volumeClaimTemplate:
            spec:
              resources:
                requests:
                  storage: 20Gi  # Was 10Gi
    ```

    Note: The storage class must support volume expansion. Check:

    ```bash
    kubectl get storageclass standard -o jsonpath='{.allowVolumeExpansion}'
    ```

## Key Concepts

- **Helm CRD limitation**: Helm installs CRDs on first install but never updates them
- **Server-side apply**: Required for CRD updates (`kubectl apply --server-side`)
- **PVC persistence**: Prometheus data survives pod restarts but PVCs may need resizing
- **ServiceMonitor label**: Apps use `release: prometheus-monitoring` to be discovered
- **Upgrade order**: CRDs → Helm chart → Validate → Promote
- **Grafana datasource**: Pre-configured with Loki at `http://loki.logging:3100`

## Rollback Plan

1. Revert chart version in the app YAML
2. ArgoCD will rollback the Helm release
3. CRDs are backward-compatible (old versions are kept alongside new ones)
4. Prometheus data in PVCs is preserved through rollback
