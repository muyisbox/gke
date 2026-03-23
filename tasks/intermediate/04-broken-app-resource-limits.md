# Task 4: Troubleshooting — Broken App (OOMKilled and Resource Issues)

**Level:** Intermediate

**Objective:** Deploy an application with resource problems and diagnose OOMKilled, CrashLoopBackOff, and eviction issues.

## Scenario

A developer deployed a Java-like application that keeps crashing. You need to figure out why.

## Setup — Deploy the Broken App

```bash
kubectl create namespace troubleshoot-resources

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-hog
  namespace: troubleshoot-resources
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-hog
  template:
    metadata:
      labels:
        app: memory-hog
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          echo "Starting application..."
          # Simulate a memory leak - allocate memory until killed
          dd if=/dev/zero of=/dev/null bs=1M &
          # Create a growing file to consume memory
          i=0
          while true; do
            head -c 10M /dev/urandom >> /tmp/data_$i
            i=$((i+1))
            echo "Allocated $((i*10))MB"
            sleep 1
          done
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "128Mi"
EOF
```

## Troubleshooting Steps

### Step 1: Observe the Problem

1. Watch the pod status:

   ```bash
   kubectl get pods -n troubleshoot-resources -w
   ```

   You'll see it go from `Running` → `OOMKilled` → `CrashLoopBackOff`.

2. Check the restart count after a few cycles:

   ```bash
   kubectl get pods -n troubleshoot-resources
   ```

### Step 2: Diagnose

3. Check the pod events:

   ```bash
   kubectl describe pod -n troubleshoot-resources -l app=memory-hog
   ```

   Look for:
   - `Last State: Terminated` with `Reason: OOMKilled`
   - `Exit Code: 137` (128 + SIGKILL signal 9)

4. Check previous container logs:

   ```bash
   kubectl logs -n troubleshoot-resources -l app=memory-hog --previous
   ```

5. Check node-level resource pressure:

   ```bash
   kubectl top nodes
   kubectl top pods -n troubleshoot-resources
   ```

### Step 3: Understand the Root Cause

6. The container's memory limit is 128Mi but the app allocates unlimited memory:
   - The Linux OOM killer terminates the process when it exceeds the cgroup memory limit
   - Exit code 137 = container was killed by SIGKILL (OOM)
   - Kubernetes restarts it, it gets OOMKilled again → CrashLoopBackOff

### Step 4: Fix the Application

7. Increase the memory limit to something appropriate:

   ```bash
   kubectl set resources deployment memory-hog -n troubleshoot-resources --limits=memory=512Mi --requests=memory=256Mi
   ```

8. But wait — the app still has a memory leak! A proper fix requires fixing the code. For now, patch the command to not leak:

   ```bash
   kubectl patch deployment memory-hog -n troubleshoot-resources --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo Running healthy app; while true; do echo alive; sleep 30; done"]}]'
   ```

9. Verify the pod stabilizes:

   ```bash
   kubectl get pods -n troubleshoot-resources -w
   ```

### Step 5: Monitor with Prometheus

10. If Grafana is available, query for OOMKilled containers:

    ```
    kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
    ```

## Cleanup

```bash
kubectl delete namespace troubleshoot-resources
```

## Troubleshooting Checklist for Resource Issues

| Symptom | Exit Code | Cause | Fix |
|---------|-----------|-------|-----|
| OOMKilled | 137 | Memory limit exceeded | Increase limit or fix leak |
| CrashLoopBackOff | 1 | Application error | Check logs |
| Evicted | N/A | Node under pressure | Add resources or scale nodes |
| Pending | N/A | No node fits requests | Reduce requests or add nodes |
| CPU Throttling | N/A | CPU limit too low | Increase CPU limit |
