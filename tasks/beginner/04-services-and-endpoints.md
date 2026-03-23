# Task 4: Services, Endpoints, and the Istio Ingress Gateway

**Level:** Beginner

**Objective:** Understand how services route traffic and how the Istio ingress gateway exposes services externally.

## Part A: Explore Internal Services

1. List all services in the `istio-system` namespace. What type is each service?
   ```bash
   kubectl get svc -n istio-system
   ```

2. Look at the `istiod` service. How many endpoints back it?
   ```bash
   kubectl get endpoints istiod -n istio-system
   ```

3. Compare the endpoint IPs to the istiod pod IPs:
   ```bash
   kubectl get pods -n istio-system -l app=istiod -o wide
   ```
   Do they match? This is how Kubernetes routes traffic from a service to pods.

## Part B: The Ingress Gateway

4. Find the external IP of the Istio ingress gateway:
   ```bash
   kubectl get svc -n istio-gateways
   ```

5. Open `gke-applications/dev/istio-gateway.yaml` and answer:
   - What ports does the gateway expose?
   - What is the autoscaling min/max?
   - What revision tag is set?

6. Describe the ingress gateway service and check the load balancer details:
   ```bash
   kubectl describe svc istio-ingressgateway -n istio-gateways
   ```

## Part C: External DNS Integration

7. Check the external-dns deployment. Open `gke-applications/dev/external-dns.yaml`:
   - What DNS provider is configured?
   - What Kubernetes resource types does it watch? (Hint: look at `sources`)
   - What is the `policy` set to? What does `upsert-only` mean?

8. View the external-dns logs to see what DNS records it's managing:
   ```bash
   kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=30
   ```

## Key Concepts

- **ClusterIP**: Internal-only, accessible within the cluster
- **LoadBalancer**: Gets an external IP from GCP, accessible from the internet
- **External DNS**: Automatically creates Cloud DNS records for LoadBalancer services
- The Istio ingress gateway is the single entry point for all external traffic
