# Task 9: Troubleshooting — Full Stack Outage (Terraform + Kubernetes + Istio + Monitoring)

**Level:** Advanced

**Objective:** Diagnose and resolve a production-like outage that involves infrastructure (Terraform/GKE), Kubernetes resources, Istio configuration, and monitoring gaps.

## Scenario

After a Terraform apply, the dev cluster is partially broken:
- Some pods can't schedule
- Services are unreachable from outside
- Monitoring is down
- ArgoCD shows multiple apps as "Degraded"

You must diagnose each issue and fix it.

## Setup — Simulate the Outage

Run these commands on the dev cluster to create the broken state:

```bash
# Problem 1: Cordon a node (simulates node maintenance without drain)
NODE=$(kubectl get nodes -o name | head -1)
kubectl cordon $NODE

# Problem 2: Delete the Istio ingress gateway service (simulates misconfiguration)
kubectl delete svc istio-ingressgateway -n istio-gateways

# Problem 3: Scale down Prometheus to 0 (simulates failed upgrade)
kubectl scale statefulset prometheus-prometheus-monitoring-kube-prometheus -n monitoring --replicas=0

# Problem 4: Add a broken NetworkPolicy
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: accidental-deny-all
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF

# Problem 5: Corrupt an ExternalSecret
kubectl annotate externalsecret --all -n argocd force-sync=broken --overwrite 2>/dev/null
```

## Troubleshooting Steps

### Issue 1: Pods Pending — Node Unavailable

1. Check pod status across namespaces:

   ```bash
   kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded'
   ```

2. Check node status:

   ```bash
   kubectl get nodes
   ```

3. Find the cordoned node:

   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,SCHEDULABLE:.spec.unschedulable
   ```

4. **Fix**: Uncordon the node:

   ```bash
   kubectl uncordon $NODE
   ```

5. Watch pending pods get scheduled:

   ```bash
   kubectl get pods -A --field-selector status.phase=Pending -w
   ```

### Issue 2: External Traffic Down — Missing Service

6. Check the ingress gateway:

   ```bash
   kubectl get svc -n istio-gateways
   ```

   The LoadBalancer service is missing — no external IP.

7. **Fix**: ArgoCD will self-heal this since the service is defined in the Helm chart. Force a sync:

   ```bash
   # On gitops cluster
   kubectl get applications -n argocd --context=gitops | grep istio-ingressgateway
   ```

   Or manually recreate by checking the Helm values in `gke-applications/dev/istio-gateway.yaml` and letting ArgoCD resync.

8. Wait for the LoadBalancer IP to be assigned:

   ```bash
   kubectl get svc -n istio-gateways -w
   ```

### Issue 3: Monitoring Down

9. Check Prometheus:

   ```bash
   kubectl get statefulset -n monitoring
   kubectl get pods -n monitoring
   ```

   Prometheus is scaled to 0.

10. **Fix**: Scale back up:

    ```bash
    kubectl scale statefulset prometheus-prometheus-monitoring-kube-prometheus -n monitoring --replicas=2
    ```

11. But pods might not start — there's a NetworkPolicy blocking all traffic!

    ```bash
    kubectl get networkpolicy -n monitoring
    kubectl describe networkpolicy accidental-deny-all -n monitoring
    ```

12. **Fix**: Delete the rogue NetworkPolicy:

    ```bash
    kubectl delete networkpolicy accidental-deny-all -n monitoring
    ```

13. Verify Prometheus pods come up:

    ```bash
    kubectl get pods -n monitoring -w
    ```

### Issue 4: ArgoCD App Sync Issues

14. On the gitops cluster, check application health:

    ```bash
    kubectl get applications -n argocd --context=gitops -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status | grep -v Healthy
    ```

15. For any Degraded apps, check what's wrong:

    ```bash
    kubectl describe application <app-name> -n argocd --context=gitops
    ```

16. **Fix**: ArgoCD's self-heal should fix most issues within minutes. For stubborn cases:

    ```bash
    # Force a refresh
    kubectl patch application <app-name> -n argocd --context=gitops --type='merge' -p='{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
    ```

### Issue 5: Verify Full Recovery

17. Run a comprehensive health check:

    ```bash
    echo "=== Nodes ==="
    kubectl get nodes

    echo "=== Unhealthy Pods ==="
    kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded'

    echo "=== Ingress Gateway ==="
    kubectl get svc -n istio-gateways

    echo "=== Monitoring ==="
    kubectl get pods -n monitoring

    echo "=== Network Policies ==="
    kubectl get networkpolicy -A

    echo "=== ArgoCD Apps ==="
    kubectl get applications -n argocd --context=gitops -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status
    ```

## Key Takeaways

- **Cordoned nodes**: Pods can't schedule but existing pods keep running
- **ArgoCD self-heal**: Fixes deleted resources automatically (if `selfHeal: true`)
- **NetworkPolicies**: A deny-all policy in a namespace can break everything in it
- **Monitoring**: If monitoring is down, you're flying blind — fix it first
- **Systematic approach**: Nodes → Pods → Services → Network → Application layer

## Incident Response Checklist

```
1. [ ] Are all nodes Ready and schedulable?
2. [ ] Are there Pending or CrashLooping pods?
3. [ ] Are critical services (ingress, DNS) reachable?
4. [ ] Is monitoring (Prometheus, Grafana) operational?
5. [ ] Are there rogue NetworkPolicies blocking traffic?
6. [ ] Is ArgoCD healthy and syncing?
7. [ ] Are ExternalSecrets syncing from GCP?
8. [ ] Check recent Terraform applies for breaking changes
```
