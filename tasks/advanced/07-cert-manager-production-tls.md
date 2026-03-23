# Task 7: Cert-Manager — Production TLS with Let's Encrypt and DNS01

**Level:** Advanced

**Objective:** Configure cert-manager with a production-grade Let's Encrypt ClusterIssuer using DNS01 challenge for wildcard TLS certificates, integrated with Istio and external-dns.

## Context

The platform already has cert-manager (v1.20.0) and external-dns (GCP Cloud DNS). This task connects them for automatic HTTPS with real certificates.

## Steps

### Part A: Understand the Current Setup

1. Check cert-manager installation:

   ```bash
   kubectl get pods -n cert-manager
   kubectl get crds | grep cert-manager
   ```

2. Review `gke-applications/dev/cert-manager.yaml`:
   - Version: 1.20.0
   - CRDs installed: true
   - Replicas: 2
   - Prometheus monitoring: enabled

3. Check what DNS zones exist:

   ```bash
   gcloud dns managed-zones list --project=cluster-dreams
   ```

### Part B: Create a GCP Service Account for DNS01

4. Cert-manager needs permissions to create DNS records for the ACME DNS01 challenge:

   ```bash
   gcloud iam service-accounts create cert-manager-dns \
     --display-name="cert-manager DNS01 solver" \
     --project=cluster-dreams

   gcloud projects add-iam-policy-binding cluster-dreams \
     --member="serviceAccount:cert-manager-dns@cluster-dreams.iam.gserviceaccount.com" \
     --role="roles/dns.admin"
   ```

5. Bind to the cert-manager Kubernetes service account via Workload Identity:

   ```bash
   gcloud iam service-accounts add-iam-policy-binding \
     cert-manager-dns@cluster-dreams.iam.gserviceaccount.com \
     --role=roles/iam.workloadIdentityUser \
     --member="serviceAccount:cluster-dreams.svc.id.goog[cert-manager/cert-manager]" \
     --project=cluster-dreams
   ```

6. Annotate the cert-manager service account:

   ```bash
   kubectl annotate serviceaccount cert-manager -n cert-manager \
     iam.gke.io/gcp-service-account=cert-manager-dns@cluster-dreams.iam.gserviceaccount.com
   ```

### Part C: Create a ClusterIssuer with Let's Encrypt

7. Create a staging issuer first (to avoid rate limits):

   ```yaml
   # letsencrypt-staging.yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-staging
   spec:
     acme:
       server: https://acme-staging-v02.api.letsencrypt.org/directory
       email: admin@yourdomain.com
       privateKeySecretRef:
         name: letsencrypt-staging-key
       solvers:
       - dns01:
           cloudDNS:
             project: cluster-dreams
   ```

8. Apply and check status:

   ```bash
   kubectl apply -f letsencrypt-staging.yaml
   kubectl describe clusterissuer letsencrypt-staging
   ```
   Wait for `Ready: True`.

### Part D: Issue a Wildcard Certificate

9. Create a wildcard certificate:

   ```yaml
   # wildcard-cert.yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: wildcard-tls
     namespace: istio-gateways
   spec:
     secretName: wildcard-tls-secret
     issuerRef:
       name: letsencrypt-staging
       kind: ClusterIssuer
     commonName: "*.yourdomain.com"
     dnsNames:
     - "*.yourdomain.com"
     - "yourdomain.com"
     duration: 2160h
     renewBefore: 720h
   ```

10. Apply and monitor:

    ```bash
    kubectl apply -f wildcard-cert.yaml
    kubectl get certificate wildcard-tls -n istio-gateways -w
    kubectl get orders -n istio-gateways
    kubectl get challenges -n istio-gateways
    ```

    Watch the DNS01 challenge: cert-manager creates a TXT record, Let's Encrypt verifies it, then issues the cert.

### Part E: Use the Certificate in an Istio Gateway

11. Create a Gateway that uses the wildcard cert:

    ```yaml
    # wildcard-gateway.yaml
    apiVersion: networking.istio.io/v1
    kind: Gateway
    metadata:
      name: wildcard-gateway
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
          credentialName: wildcard-tls-secret
        hosts:
        - "*.yourdomain.com"
    ```

12. Any service can now use this gateway for HTTPS:

    ```yaml
    apiVersion: networking.istio.io/v1
    kind: VirtualService
    metadata:
      name: myservice
      namespace: default
    spec:
      hosts:
      - "myservice.yourdomain.com"
      gateways:
      - istio-gateways/wildcard-gateway
      http:
      - route:
        - destination:
            host: myservice
    ```

### Part F: Production Issuer

13. Once validated with staging, create the production issuer:

    ```yaml
    # letsencrypt-prod.yaml
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: admin@yourdomain.com
        privateKeySecretRef:
          name: letsencrypt-prod-key
        solvers:
        - dns01:
            cloudDNS:
              project: cluster-dreams
    ```

14. Update the Certificate to use the production issuer:

    ```bash
    kubectl patch certificate wildcard-tls -n istio-gateways --type='json' \
      -p='[{"op":"replace","path":"/spec/issuerRef/name","value":"letsencrypt-prod"}]'
    ```

## Key Concepts

- **DNS01 challenge**: Proves domain ownership by creating a DNS TXT record (required for wildcards)
- **HTTP01 challenge**: Simpler but doesn't support wildcards
- **Wildcard certificates**: One cert covers all subdomains (`*.yourdomain.com`)
- **Workload Identity**: cert-manager authenticates to Cloud DNS without service account keys
- **credentialName**: Istio Gateway references the TLS secret by name
- **Auto-renewal**: cert-manager renews before `renewBefore` expiry

## Troubleshooting

```bash
# Check challenge status
kubectl get challenges -A
kubectl describe challenge <name> -n istio-gateways

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Common issues:
# - DNS propagation delay (wait 60-120s)
# - Missing DNS permissions (check GCP SA bindings)
# - Rate limits (use staging issuer first)
```
