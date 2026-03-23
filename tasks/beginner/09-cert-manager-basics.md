# Task 9: Cert-Manager — Understanding TLS Certificate Management

**Level:** Beginner

**Objective:** Explore cert-manager and understand how it automates TLS certificate management.

## Part A: Explore the Installation

1. Open `gke-applications/dev/cert-manager.yaml` and note:
   - What version is deployed?
   - Are CRDs installed by the chart?
   - How many replicas?
   - Is Prometheus monitoring enabled?

2. Verify cert-manager is running:
   ```bash
   kubectl get pods -n cert-manager
   kubectl get deployments -n cert-manager
   ```

3. List the CRDs that cert-manager installed:
   ```bash
   kubectl get crds | grep cert-manager
   ```
   You should see: certificates, issuers, clusterissuers, certificaterequests, orders, challenges.

## Part B: Check Existing Certificates

4. Are there any certificates or issuers already created?
   ```bash
   kubectl get certificates -A
   kubectl get clusterissuers
   kubectl get issuers -A
   ```

## Part C: Create a Self-Signed Certificate

5. Create a ClusterIssuer and Certificate:
   ```yaml
   # self-signed-test.yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: selfsigned-test
   spec:
     selfSigned: {}
   ---
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: test-cert
     namespace: default
   spec:
     secretName: test-tls-secret
     issuerRef:
       name: selfsigned-test
       kind: ClusterIssuer
     commonName: myapp.example.com
     dnsNames:
     - myapp.example.com
     - www.myapp.example.com
     duration: 2160h    # 90 days
     renewBefore: 360h  # Renew 15 days before expiry
   ```

6. Apply and check the status:
   ```bash
   kubectl apply -f self-signed-test.yaml
   kubectl get certificate test-cert -n default
   kubectl describe certificate test-cert -n default
   ```
   Is the certificate `Ready`?

7. Check the generated TLS secret:
   ```bash
   kubectl get secret test-tls-secret -n default
   kubectl describe secret test-tls-secret -n default
   ```
   What keys does it contain? (`tls.crt`, `tls.key`, `ca.crt`)

8. View the certificate details:
   ```bash
   kubectl get secret test-tls-secret -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | head -20
   ```

## Cleanup

```bash
kubectl delete -f self-signed-test.yaml
kubectl delete secret test-tls-secret -n default
```

## Key Concepts

- **ClusterIssuer**: Cluster-wide certificate authority (can issue certs in any namespace)
- **Issuer**: Namespace-scoped certificate authority
- **Certificate**: Declares what cert you want — cert-manager handles creation and renewal
- **Secret**: The actual TLS cert and key are stored in a Kubernetes secret
- In production, you'd use Let's Encrypt or a private CA instead of self-signed
