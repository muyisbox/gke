# Task 3: Troubleshooting — Cascading Failure (Multi-Layer Debugging)

**Level:** Advanced

**Objective:** Debug a complex application failure that spans multiple layers: Deployment, Service, Istio, ExternalSecret, and ConfigMap.

## Scenario

The platform team deployed a new microservice that reads database credentials from an ExternalSecret and connects to a backend behind the Istio mesh. Nothing works. There are 5 separate issues — fix them all.

## Setup — Deploy the Broken Stack

```bash
kubectl create namespace troubleshoot-cascade
kubectl label namespace troubleshoot-cascade istio-injection=enabled

cat <<'EOF' | kubectl apply -f -
# Issue 1: Wrong secret reference
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-credentials
  namespace: troubleshoot-cascade
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: gcp-secret-manager
    kind: ClusterSecretStore
  target:
    name: app-db-secret
  data:
  - secretKey: DB_URL
    remoteRef:
      key: nonexistent-secret-name
---
# Issue 2: ConfigMap with wrong key name
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: troubleshoot-cascade
data:
  APP_PORT: "3000"
  LOG_LEVEL: "info"
---
# Issue 3: Deployment references wrong secret and configmap key
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: troubleshoot-cascade
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: api
        image: nginx:1.25
        ports:
        - containerPort: 3000
        env:
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: app-db-secret
              key: DATABASE_URL
        - name: PORT
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: PORT
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
---
# Issue 4: Service targets wrong port
apiVersion: v1
kind: Service
metadata:
  name: api-server
  namespace: troubleshoot-cascade
spec:
  selector:
    app: api-server-v2
  ports:
  - name: http
    port: 80
    targetPort: 8080
---
# Issue 5: VirtualService references wrong host
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: api-server
  namespace: troubleshoot-cascade
spec:
  hosts:
  - api-service
  http:
  - route:
    - destination:
        host: api-service
        port:
          number: 80
EOF
```

## Troubleshooting Steps

### Layer 1: ExternalSecret

1. Check the ExternalSecret status:

   ```bash
   kubectl get externalsecrets -n troubleshoot-cascade
   kubectl describe externalsecret app-credentials -n troubleshoot-cascade
   ```

2. **Issue**: The secret `nonexistent-secret-name` doesn't exist in GCP Secret Manager.
3. **Fix**: Either create the GCP secret or change the `remoteRef.key` to an existing secret. For this exercise, create the K8s secret manually:

   ```bash
   kubectl create secret generic app-db-secret -n troubleshoot-cascade --from-literal=DB_URL="postgresql://user:pass@db:5432/myapp"
   ```

### Layer 2: Pod Won't Start

4. Check the pods:

   ```bash
   kubectl get pods -n troubleshoot-cascade
   kubectl describe pod -l app=api-server -n troubleshoot-cascade
   ```

5. **Issue**: The pod fails to start because it references `key: DATABASE_URL` but the secret has `key: DB_URL`. Also, `key: PORT` doesn't exist in the ConfigMap (it's `APP_PORT`).
6. **Fix**:

   ```bash
   kubectl set env deployment/api-server -n troubleshoot-cascade --containers=api DB_URL- PORT-
   kubectl set env deployment/api-server -n troubleshoot-cascade --containers=api \
     --from=secret/app-db-secret \
     --keys=DB_URL
   kubectl set env deployment/api-server -n troubleshoot-cascade --containers=api \
     PORT=3000
   ```

   Or patch the deployment to fix the references.

### Layer 3: Service Selector Mismatch

7. Once the pod is running, test the service:

   ```bash
   kubectl get endpoints api-server -n troubleshoot-cascade
   ```

8. **Issue**: The endpoint list is empty. The service selector is `app: api-server-v2` but pods have `app: api-server`.
9. **Fix**:

   ```bash
   kubectl patch svc api-server -n troubleshoot-cascade -p '{"spec":{"selector":{"app":"api-server"}}}'
   ```

10. Also fix the targetPort (pods listen on 3000, not 8080):

    ```bash
    kubectl patch svc api-server -n troubleshoot-cascade --type='json' -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":3000}]'
    ```

### Layer 4: Service Port Mismatch

11. Verify endpoints are populated:

    ```bash
    kubectl get endpoints api-server -n troubleshoot-cascade
    ```

### Layer 5: VirtualService

12. Check the VirtualService:

    ```bash
    kubectl get vs -n troubleshoot-cascade -o yaml
    ```

13. **Issue**: The VirtualService references `api-service` instead of `api-server`.
14. **Fix**:

    ```bash
    kubectl patch virtualservice api-server -n troubleshoot-cascade --type='json' -p='[
      {"op":"replace","path":"/spec/hosts/0","value":"api-server"},
      {"op":"replace","path":"/spec/http/0/route/0/destination/host","value":"api-server"}
    ]'
    ```

### Verify Everything Works

15. Test the full chain:

    ```bash
    kubectl run test-client --image=busybox -n troubleshoot-cascade --rm -it -- wget -qO- --timeout=5 http://api-server
    ```

## Cleanup

```bash
kubectl delete namespace troubleshoot-cascade
```

## Debugging Methodology

When faced with a complex failure, work from the bottom up:

```
1. ExternalSecret → Is the secret syncing?
2. Secret/ConfigMap → Do the keys exist and match?
3. Pod → Is it starting? Check events, logs, env vars
4. Service → Does the selector match? Are endpoints populated?
5. VirtualService → Does the host name match the service?
6. Gateway → Is external traffic routing correctly?
```

Each layer depends on the one below it. Fix from the bottom up.
