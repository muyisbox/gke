# Task 7: Troubleshooting — Broken App (Istio Sidecar and mTLS Issues)

**Level:** Intermediate

**Objective:** Deploy an application that fails due to Istio sidecar injection and mTLS configuration issues.

## Scenario

A developer deployed a new service but it can't communicate with existing services in the mesh. Traffic is being rejected.

## Setup — Deploy the Broken App

```bash
# Create namespace WITHOUT Istio injection label
kubectl create namespace troubleshoot-istio

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-app
  namespace: troubleshoot-istio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client-app
  template:
    metadata:
      labels:
        app: client-app
    spec:
      containers:
      - name: client
        image: busybox:1.36
        command: ["sh", "-c", "while true; do wget -qO- --timeout=3 http://server-app.troubleshoot-istio:8080 2>&1; sleep 5; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-app
  namespace: troubleshoot-istio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: server-app
  template:
    metadata:
      labels:
        app: server-app
    spec:
      containers:
      - name: server
        image: nginx:1.25
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: server-app
  namespace: troubleshoot-istio
spec:
  selector:
    app: server-app
  ports:
  - port: 8080
    targetPort: 80
EOF
```

## Troubleshooting Steps

### Issue 1: No Istio Sidecar

1. Check the pods — how many containers per pod?

   ```bash
   kubectl get pods -n troubleshoot-istio
   ```

   You should see `1/1` — meaning no Istio sidecar. Compare to bookinfo:

   ```bash
   kubectl get pods -n bookinfo
   ```

   Bookinfo pods show `2/2` (app + sidecar).

2. Check the namespace labels:

   ```bash
   kubectl get namespace troubleshoot-istio --show-labels
   ```

   Compare to a namespace with injection:

   ```bash
   kubectl get namespace bookinfo --show-labels
   ```

3. **Fix**: Enable Istio sidecar injection on the namespace:

   ```bash
   kubectl label namespace troubleshoot-istio istio-injection=enabled
   ```

   Note: In this platform, the ArgoCD sync option `managedNamespaceMetadata` applies the label `istio.io/revy: stable` automatically. Check `templates/apps-values.yaml` for this.

4. Restart the deployments to pick up the sidecar:

   ```bash
   kubectl rollout restart deployment -n troubleshoot-istio
   kubectl get pods -n troubleshoot-istio -w
   ```

   Now you should see `2/2`.

### Issue 2: Strict mTLS Rejection

5. Now apply a strict mTLS policy:

   ```yaml
   # strict-mtls.yaml
   apiVersion: security.istio.io/v1
   kind: PeerAuthentication
   metadata:
     name: strict
     namespace: troubleshoot-istio
   spec:
     mtls:
       mode: STRICT
   ```

   ```bash
   kubectl apply -f strict-mtls.yaml
   ```

6. Check client logs — traffic should still work (both pods now have sidecars):

   ```bash
   kubectl logs -n troubleshoot-istio -l app=client-app -c client --tail=5
   ```

7. Now deploy a pod WITHOUT a sidecar and try to reach the server:

   ```bash
   kubectl run no-mesh --image=busybox -n troubleshoot-istio \
     --overrides='{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}' \
     -- sh -c "while true; do wget -qO- --timeout=3 http://server-app:8080 2>&1; echo; sleep 5; done"
   ```

8. Check its logs:

   ```bash
   kubectl logs no-mesh -n troubleshoot-istio --tail=5
   ```

   It should fail with connection reset — the server requires mTLS but this pod has no certificate.

9. Verify in Kiali (port-forward `kubectl port-forward svc/kiali -n istio-system 20001:20001`):
   - Look for red edges in the traffic graph
   - The lock icon on connections indicates mTLS

### Issue 3: Port Name Convention

10. Check the service definition:

    ```bash
    kubectl get svc server-app -n troubleshoot-istio -o yaml
    ```

    Istio uses port names to determine protocol. If the port name doesn't follow the convention (`http-`, `grpc-`, `tcp-`), Istio treats it as opaque TCP.

## Cleanup

```bash
kubectl delete namespace troubleshoot-istio
```

## Troubleshooting Checklist for Istio Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| 1/1 containers (no sidecar) | Namespace missing injection label | `kubectl label ns <ns> istio-injection=enabled` |
| Connection reset between services | Strict mTLS, missing sidecar on caller | Add sidecar or change mTLS to PERMISSIVE |
| 503 errors | DestinationRule mismatch or missing | Check DR subsets match deployment labels |
| No traffic in Kiali | Sidecar not injected | Restart pods after enabling injection |
| gRPC fails through gateway | Port not named `grpc-*` | Rename service port |
