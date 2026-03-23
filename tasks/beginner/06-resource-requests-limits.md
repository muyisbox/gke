# Task 6: Resource Requests, Limits, and the VPA

**Level:** Beginner

**Objective:** Understand resource management, how it affects scheduling, and how VPA recommends adjustments.

## Part A: Inspect Current Resource Configuration

1. Open `gke-applications/dev/external-dns.yaml` and find the resource requests and limits:
   - CPU request: ?
   - Memory request: ?
   - Memory limit: ?

2. Verify these match the running pod:
   ```bash
   kubectl get pod -n external-dns -l app.kubernetes.io/name=external-dns -o jsonpath='{.items[0].spec.containers[0].resources}' | python3 -m json.tool
   ```

3. Check the `reloader` app (`gke-applications/dev/reloader.yaml`):
   - What are its resource requests?
   - Is `readOnlyRootFilesystem` enabled? Why is this a security best practice?

4. View resource usage vs requests across the cluster:
   ```bash
   kubectl top pods -A --sort-by=memory | head -20
   kubectl top nodes
   ```

## Part B: Understand Scheduling Impact

5. What happens when a pod requests more resources than any node can provide? Test it:
   ```bash
   cat <<'EOF' | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: too-big
     namespace: default
   spec:
     containers:
     - name: nginx
       image: nginx
       resources:
         requests:
           memory: "999Gi"
           cpu: "999"
   EOF
   ```

6. Check the pod status and events:
   ```bash
   kubectl get pod too-big
   kubectl describe pod too-big
   ```
   What event message do you see? This is a `Pending` pod due to insufficient resources.

7. Clean up: `kubectl delete pod too-big`

## Part C: Vertical Pod Autoscaler

8. Check VPA is running (`gke-applications/dev/vpa.yaml`):
   ```bash
   kubectl get pods -n vpa
   ```

9. Create a VPA in recommendation-only mode:
   ```yaml
   # test-vpa.yaml
   apiVersion: autoscaling.k8s.io/v1
   kind: VerticalPodAutoscaler
   metadata:
     name: reloader-vpa
     namespace: reloader
   spec:
     targetRef:
       apiVersion: "apps/v1"
       kind: Deployment
       name: reloader-reloader
     updatePolicy:
       updateMode: "Off"
   ```

10. Apply, wait 2-3 minutes, then check recommendations:
    ```bash
    kubectl apply -f test-vpa.yaml
    kubectl describe vpa reloader-vpa -n reloader
    ```
    Compare the VPA's recommended CPU/memory to the current requests.

11. Clean up: `kubectl delete -f test-vpa.yaml`

## Key Concepts

- **Requests**: Guaranteed resources — used for scheduling decisions
- **Limits**: Maximum resources — pod gets OOMKilled if it exceeds memory limit
- **VPA**: Analyzes actual usage and recommends appropriate request/limit values
- Setting requests too low → pod gets evicted; too high → wastes cluster resources
