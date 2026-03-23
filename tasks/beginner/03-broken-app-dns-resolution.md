# Task 3: Troubleshooting — Broken App (DNS Resolution Failure)

**Level:** Beginner

**Objective:** Deploy a broken application and troubleshoot DNS resolution issues within the cluster.

## Scenario

A developer deployed an application that can't connect to its backend service. You need to figure out why.

## Setup — Deploy the Broken App

```bash
kubectl create namespace troubleshoot-dns

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: troubleshoot-dns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: busybox:1.36
        command: ["sh", "-c", "while true; do wget -qO- --timeout=2 http://backend-api:8080/health 2>&1; sleep 5; done"]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: troubleshoot-dns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF
```

## Troubleshooting Steps

1. Check the pods — are they running?
   ```bash
   kubectl get pods -n troubleshoot-dns
   ```

2. Check the frontend logs — what error do you see?
   ```bash
   kubectl logs -n troubleshoot-dns -l app=frontend
   ```

3. The frontend is trying to reach `backend-api:8080`. Is there a Service for this? Check:
   ```bash
   kubectl get svc -n troubleshoot-dns
   ```

4. **Root Cause #1**: There is no Service object. Create one, but notice there are TWO issues:
   ```bash
   kubectl expose deployment backend -n troubleshoot-dns --name=backend-api --port=8080 --target-port=80
   ```

5. Now check the frontend logs again. Is it still failing? Why?
   ```bash
   kubectl logs -n troubleshoot-dns -l app=frontend --tail=5
   ```

6. **Root Cause #2**: The service name matches now, but check if DNS is resolving:
   ```bash
   kubectl exec -n troubleshoot-dns -l app=frontend -- nslookup backend-api
   ```

7. Verify the backend pod is actually serving on port 80:
   ```bash
   kubectl exec -n troubleshoot-dns -l app=frontend -- wget -qO- --timeout=2 http://backend-api:8080/
   ```

8. It should work now. Check the frontend logs to confirm:
   ```bash
   kubectl logs -n troubleshoot-dns -l app=frontend --tail=5
   ```

## Cleanup

```bash
kubectl delete namespace troubleshoot-dns
```

## Key Lessons

- Services provide stable DNS names for pods
- The Service `port` is what clients connect to; `targetPort` is where the pod listens
- DNS resolution uses `<service-name>.<namespace>.svc.cluster.local`
- Always check: Pod running → Service exists → DNS resolves → Port mapping correct
