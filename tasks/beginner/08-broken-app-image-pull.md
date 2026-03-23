# Task 8: Troubleshooting — Broken App (ImagePullBackOff)

**Level:** Beginner

**Objective:** Deploy a broken application and diagnose an image pull failure.

## Scenario

A developer pushed a deployment with a typo in the image name. The pod won't start.

## Setup — Deploy the Broken App

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: ngnix:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            memory: "128Mi"
EOF
```

## Troubleshooting Steps

1. Check the pod status:
   ```bash
   kubectl get pods -l app=web-app
   ```
   You should see `ErrImagePull` or `ImagePullBackOff`.

2. Describe the pod to see the events:
   ```bash
   kubectl describe pod -l app=web-app
   ```
   Look at the Events section — what error message do you see?

3. Identify the problem: The image name is `ngnix` (typo) instead of `nginx`.

4. Fix it:
   ```bash
   kubectl set image deployment/web-app web=nginx:1.25
   ```

5. Watch the pods recover:
   ```bash
   kubectl get pods -l app=web-app -w
   ```

6. Verify the fix:
   ```bash
   kubectl describe pod -l app=web-app | grep "Image:"
   ```

## Cleanup

```bash
kubectl delete deployment web-app
```

## Troubleshooting Checklist for Image Issues

1. `kubectl get pods` — check status column (ErrImagePull, ImagePullBackOff)
2. `kubectl describe pod` — check Events for pull error details
3. Common causes:
   - Typo in image name
   - Image tag doesn't exist
   - Private registry without imagePullSecrets
   - Network issues reaching the registry
4. `kubectl set image` to fix in-place, or edit the deployment YAML
