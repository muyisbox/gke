# Task 6: External DNS + Cert-Manager + Istio Gateway — End-to-End HTTPS

**Level:** Intermediate

**Objective:** Configure a complete HTTPS ingress path: Istio Gateway → cert-manager TLS certificate → external-dns DNS record.

## Context

This platform has three components that work together for HTTPS:
- **Istio Gateway**: Accepts external traffic
- **cert-manager**: Issues TLS certificates
- **external-dns**: Creates DNS records pointing to the gateway's external IP

## Steps

### Part A: Understand the External DNS Configuration

1. Open `gke-applications/dev/external-dns.yaml` and note:
   - Provider: `google` (Cloud DNS)
   - Sources: `service`, `ingress`, `istio-gateway`
   - Policy: `upsert-only` (creates/updates but never deletes records)

2. Check external-dns is running and what records it's managing:

   ```bash
   kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50
   ```

3. List your Cloud DNS managed zones:

   ```bash
   gcloud dns managed-zones list --project=cluster-dreams
   ```

### Part B: Create a TLS Certificate with Cert-Manager

4. First, create a ClusterIssuer (use self-signed for this exercise; in production you'd use Let's Encrypt):

   ```yaml
   # cluster-issuer.yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: selfsigned-issuer
   spec:
     selfSigned: {}
   ```

5. Create a Certificate for your app:

   ```yaml
   # app-certificate.yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: myapp-tls
     namespace: istio-gateways
   spec:
     secretName: myapp-tls-secret
     issuerRef:
       name: selfsigned-issuer
       kind: ClusterIssuer
     commonName: myapp.example.com
     dnsNames:
     - myapp.example.com
   ```

6. Apply and verify:

   ```bash
   kubectl apply -f cluster-issuer.yaml
   kubectl apply -f app-certificate.yaml
   kubectl get certificate myapp-tls -n istio-gateways
   kubectl get secret myapp-tls-secret -n istio-gateways
   ```

### Part C: Create the Istio Gateway with TLS

7. Create a Gateway that uses the TLS certificate:

   ```yaml
   # myapp-gateway.yaml
   apiVersion: networking.istio.io/v1
   kind: Gateway
   metadata:
     name: myapp-gateway
     namespace: istio-gateways
   spec:
     selector:
       istio: ingressgateway
     servers:
     - port:
         number: 443
         name: https
         protocol: HTTPS
       tls:
         mode: SIMPLE
         credentialName: myapp-tls-secret
       hosts:
       - myapp.example.com
     - port:
         number: 80
         name: http
         protocol: HTTP
       tls:
         httpsRedirect: true
       hosts:
       - myapp.example.com
   ```

8. Create a VirtualService and backend:

   ```yaml
   # myapp-vs.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: myapp
   ---
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: myapp
     namespace: myapp
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: myapp
     template:
       metadata:
         labels:
           app: myapp
       spec:
         containers:
         - name: nginx
           image: nginx:1.25
           ports:
           - containerPort: 80
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: myapp
     namespace: myapp
   spec:
     selector:
       app: myapp
     ports:
     - port: 80
   ---
   apiVersion: networking.istio.io/v1
   kind: VirtualService
   metadata:
     name: myapp
     namespace: myapp
   spec:
     hosts:
     - myapp.example.com
     gateways:
     - istio-gateways/myapp-gateway
     http:
     - route:
       - destination:
           host: myapp
           port:
             number: 80
   ```

9. Apply everything:

   ```bash
   kubectl apply -f myapp-gateway.yaml
   kubectl apply -f myapp-vs.yaml
   ```

### Part D: Verify the Full Chain

10. Check external-dns logs to see if it picked up the gateway:

    ```bash
    kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=10
    ```

11. Test the connection (use the ingress gateway IP directly since DNS may not resolve for example.com):

    ```bash
    GATEWAY_IP=$(kubectl get svc istio-ingressgateway -n istio-gateways -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    curl -k --resolve myapp.example.com:443:$GATEWAY_IP https://myapp.example.com
    ```

## Cleanup

```bash
kubectl delete -f myapp-vs.yaml
kubectl delete -f myapp-gateway.yaml
kubectl delete -f app-certificate.yaml
kubectl delete -f cluster-issuer.yaml
kubectl delete secret myapp-tls-secret -n istio-gateways
kubectl delete namespace myapp
```

## Key Concepts

- **Traffic flow**: Client → Cloud DNS → Load Balancer IP → Istio Gateway (TLS termination) → VirtualService → Service → Pod
- **cert-manager** automates certificate issuance and renewal
- **external-dns** watches Istio Gateways and creates DNS records
- **credentialName** in the Gateway references the TLS secret created by cert-manager
- In production, use Let's Encrypt with DNS01 challenge for real certificates
