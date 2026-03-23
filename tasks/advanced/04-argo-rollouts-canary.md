# Task 4: Argo Rollouts — Canary Deployment with Istio Traffic Management

**Level:** Advanced

**Objective:** Implement a canary deployment using Argo Rollouts integrated with Istio traffic management for fine-grained traffic splitting.

## Context

Argo Rollouts (deployed via `gke-applications/*/argo-rollouts.yaml`, chart v2.40.6) extends Kubernetes with advanced deployment strategies. Combined with Istio, it can automatically shift traffic percentages during a canary rollout.

## Steps

### Part A: Set Up the Canary Infrastructure

1. Create the application namespace and resources:

   ```yaml
   # canary-demo.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: canary-demo
     labels:
       istio-injection: enabled
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: canary-app
     namespace: canary-demo
   spec:
     selector:
       app: canary-app
     ports:
     - port: 80
       targetPort: 80
       name: http
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: canary-app-canary
     namespace: canary-demo
   spec:
     selector:
       app: canary-app
     ports:
     - port: 80
       targetPort: 80
       name: http
   ---
   apiVersion: networking.istio.io/v1
   kind: VirtualService
   metadata:
     name: canary-app-vsvc
     namespace: canary-demo
   spec:
     hosts:
     - canary-app
     http:
     - route:
       - destination:
           host: canary-app
         weight: 100
       - destination:
           host: canary-app-canary
         weight: 0
   ---
   apiVersion: networking.istio.io/v1
   kind: DestinationRule
   metadata:
     name: canary-app-destrule
     namespace: canary-demo
   spec:
     host: canary-app
     subsets:
     - name: stable
       labels:
         app: canary-app
     - name: canary
       labels:
         app: canary-app
   ```

2. Create the Rollout:

   ```yaml
   # canary-rollout.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Rollout
   metadata:
     name: canary-app
     namespace: canary-demo
   spec:
     replicas: 4
     revisionHistoryLimit: 2
     selector:
       matchLabels:
         app: canary-app
     template:
       metadata:
         labels:
           app: canary-app
         annotations:
           sidecar.istio.io/inject: "true"
       spec:
         containers:
         - name: app
           image: nginx:1.25
           ports:
           - containerPort: 80
           resources:
             requests:
               cpu: 50m
               memory: 64Mi
     strategy:
       canary:
         canaryService: canary-app-canary
         stableService: canary-app
         trafficRouting:
           istio:
             virtualService:
               name: canary-app-vsvc
         steps:
         - setWeight: 10
         - pause: {duration: 30s}
         - setWeight: 30
         - pause: {duration: 30s}
         - setWeight: 50
         - pause: {duration: 30s}
         - setWeight: 80
         - pause: {duration: 30s}
   ```

3. Apply everything:

   ```bash
   kubectl apply -f canary-demo.yaml
   kubectl apply -f canary-rollout.yaml
   ```

### Part B: Trigger a Canary Rollout

4. Wait for the initial rollout to stabilize:

   ```bash
   kubectl argo rollouts get rollout canary-app -n canary-demo -w
   ```

5. Trigger an update:

   ```bash
   kubectl argo rollouts set image canary-app app=nginx:1.26 -n canary-demo
   ```

6. Watch the canary progress through the steps:

   ```bash
   kubectl argo rollouts get rollout canary-app -n canary-demo -w
   ```

7. Check the VirtualService to see Istio traffic weights being modified:

   ```bash
   kubectl get vs canary-app-vsvc -n canary-demo -o yaml
   ```

   Watch the weights change: 10/90 → 30/70 → 50/50 → 80/20 → 100/0

### Part C: Abort and Rollback

8. Trigger another update and abort mid-rollout:

   ```bash
   kubectl argo rollouts set image canary-app app=nginx:1.27-invalid -n canary-demo
   ```

9. Wait until it reaches the 30% step, then abort:

   ```bash
   kubectl argo rollouts abort canary-app -n canary-demo
   ```

10. Watch the rollback:

    ```bash
    kubectl argo rollouts get rollout canary-app -n canary-demo -w
    ```

    Traffic shifts back to 100% stable.

### Part D: Monitor in Kiali

11. Port-forward Kiali and watch the traffic split in real-time:

    ```bash
    kubectl port-forward svc/kiali -n istio-system 20001:20001
    ```

    Generate traffic while the canary is in progress:

    ```bash
    kubectl run traffic-gen --image=busybox -n canary-demo --rm -it -- sh -c "while true; do wget -qO- http://canary-app; done"
    ```

## Cleanup

```bash
kubectl delete namespace canary-demo
```

## Key Concepts

- **Argo Rollouts** automates the canary steps — no manual traffic shifting
- **Istio integration**: Rollouts modifies the VirtualService weights automatically
- **Steps**: Define the rollout pace (weight + pause duration)
- **Abort**: Immediately rolls back all traffic to the stable version
- In production, add **analysis** steps (Prometheus queries) to auto-promote or abort based on error rates
