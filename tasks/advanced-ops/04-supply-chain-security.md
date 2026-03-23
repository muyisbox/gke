# Task 4: Supply Chain Security — Image Signing, Vulnerability Scanning, and Admission Control

**Level:** Advanced Operations

**Objective:** Implement a complete supply chain security pipeline: scan images for vulnerabilities with Trivy, sign images with cosign, store attestations in Artifact Registry, and enforce signed-image-only policies with Kyverno.

## Context

This platform already uses Trivy and Checkov in the CI/CD pipeline (`cicd/cloudbuild.yaml`). This task extends that to enforce supply chain integrity at the cluster admission level — images that haven't been scanned and signed are rejected.

## Steps

### Part A: Set Up Image Vulnerability Scanning

1. Install Trivy locally if not already available:

   ```bash
   brew install trivy  # macOS
   ```

2. Scan a public image to understand the output:

   ```bash
   trivy image --severity HIGH,CRITICAL nginx:1.25
   ```

3. Scan an image from your Artifact Registry:

   ```bash
   trivy image us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
   ```

4. Generate a scan report in JSON format (needed for attestations):

   ```bash
   trivy image --format json --output /tmp/scan-report.json \
     us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
   ```

5. Check if any CRITICAL vulnerabilities were found:

   ```bash
   cat /tmp/scan-report.json | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL") | .VulnerabilityID'
   ```

### Part B: Sign Images with Cosign

6. Install cosign:

   ```bash
   brew install cosign  # macOS
   ```

7. Generate a cosign key pair (for this exercise; in production use KMS):

   ```bash
   cosign generate-key-pair
   # Creates cosign.key (private) and cosign.pub (public)
   ```

8. Sign an image in your Artifact Registry:

   ```bash
   cosign sign --key cosign.key \
     us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
   ```

   Cosign stores the signature as an OCI artifact alongside the image.

9. Verify the signature:

   ```bash
   cosign verify --key cosign.pub \
     us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
   ```

### Part C: Use Google KMS for Keyless Signing (Production)

10. In production, use GCP KMS instead of local keys:

    ```bash
    # Create a KMS keyring and key
    gcloud kms keyrings create cosign-keyring \
      --location=us-central1 \
      --project=cluster-dreams

    gcloud kms keys create cosign-key \
      --keyring=cosign-keyring \
      --location=us-central1 \
      --purpose=asymmetric-signing \
      --default-algorithm=ec-sign-p256-sha256 \
      --project=cluster-dreams
    ```

11. Sign with KMS:

    ```bash
    cosign sign --key gcpkms://projects/cluster-dreams/locations/us-central1/keyRings/cosign-keyring/cryptoKeys/cosign-key \
      us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
    ```

12. Verify with KMS:

    ```bash
    cosign verify --key gcpkms://projects/cluster-dreams/locations/us-central1/keyRings/cosign-keyring/cryptoKeys/cosign-key \
      us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
    ```

### Part D: Enforce Image Signatures with Kyverno

13. Store the cosign public key as a ConfigMap:

    ```bash
    kubectl create configmap cosign-pub-key \
      --from-file=cosign.pub=cosign.pub \
      -n kyverno
    ```

14. Create a Kyverno policy that verifies image signatures:

    ```yaml
    # policies/verify-image-signatures.yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: verify-image-signatures
      annotations:
        policies.kyverno.io/title: Verify Image Signatures
        policies.kyverno.io/category: Supply Chain Security
        policies.kyverno.io/severity: critical
        policies.kyverno.io/description: >-
          Verifies that container images from Artifact Registry
          are signed with our cosign key.
    spec:
      validationFailureAction: Enforce
      webhookTimeoutSeconds: 30
      rules:
      - name: verify-signature
        match:
          any:
          - resources:
              kinds:
              - Pod
        imageExtractors:
          Pod:
            containers:
            - name: containers
              path: /spec/containers/*/image
            - name: initContainers
              path: /spec/initContainers/*/image
        verifyImages:
        - imageReferences:
          - "us-central1-docker.pkg.dev/cluster-dreams/*"
          attestors:
          - count: 1
            entries:
            - keys:
                publicKeys: |-
                  -----BEGIN PUBLIC KEY-----
                  <INSERT YOUR cosign.pub CONTENT HERE>
                  -----END PUBLIC KEY-----
          mutateDigest: true
          verifyDigest: true
    ```

    Replace the public key with your actual `cosign.pub` content.

15. Apply and test:

    ```bash
    kubectl apply -f policies/verify-image-signatures.yaml

    # This should SUCCEED (image is signed):
    kubectl run test-signed \
      --image=us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25 \
      -n default --dry-run=server

    # This should FAIL (image is not signed):
    kubectl run test-unsigned \
      --image=us-central1-docker.pkg.dev/cluster-dreams/docker-images/some-unsigned:latest \
      -n default --dry-run=server
    ```

### Part E: Integrate into the CI/CD Pipeline

16. Add image signing to `cicd/cloudbuild.yaml` after the build step. Create a new step:

    ```yaml
    - id: 'sign-image'
      name: 'gcr.io/projectsigstore/cosign'
      args:
      - 'sign'
      - '--key'
      - 'gcpkms://projects/cluster-dreams/locations/us-central1/keyRings/cosign-keyring/cryptoKeys/cosign-key'
      - '${_IMAGE_URI}'
      env:
      - 'COSIGN_YES=true'
    ```

17. Add vulnerability gate — fail the pipeline if CRITICAL vulns found:

    ```yaml
    - id: 'vulnerability-gate'
      name: 'aquasec/trivy'
      args:
      - 'image'
      - '--exit-code'
      - '1'
      - '--severity'
      - 'CRITICAL'
      - '${_IMAGE_URI}'
    ```

    `--exit-code 1` makes Trivy return a non-zero exit code if vulnerabilities are found, failing the pipeline step.

### Part F: Generate and Attach Attestations

18. Create a vulnerability attestation and attach it to the image:

    ```bash
    # Generate SBOM
    trivy image --format cyclonedx --output /tmp/sbom.json \
      us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25

    # Attach SBOM as attestation
    cosign attest --key cosign.key \
      --predicate /tmp/sbom.json \
      --type cyclonedx \
      us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
    ```

19. Verify the attestation:

    ```bash
    cosign verify-attestation --key cosign.pub \
      --type cyclonedx \
      us-central1-docker.pkg.dev/cluster-dreams/docker-images/nginx:1.25
    ```

### Part G: Kyverno Policy for Attestation Verification

20. Create a policy that requires vulnerability attestations:

    ```yaml
    # policies/verify-vulnerability-scan.yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: verify-vulnerability-scan
      annotations:
        policies.kyverno.io/title: Verify Vulnerability Scan Attestation
        policies.kyverno.io/category: Supply Chain Security
        policies.kyverno.io/severity: high
    spec:
      validationFailureAction: Audit
      webhookTimeoutSeconds: 30
      rules:
      - name: check-vulnerability-attestation
        match:
          any:
          - resources:
              kinds:
              - Pod
        verifyImages:
        - imageReferences:
          - "us-central1-docker.pkg.dev/cluster-dreams/*"
          attestations:
          - type: https://cyclonedx.org/bom
            attestors:
            - count: 1
              entries:
              - keys:
                  publicKeys: |-
                    -----BEGIN PUBLIC KEY-----
                    <INSERT YOUR cosign.pub CONTENT HERE>
                    -----END PUBLIC KEY-----
    ```

## Supply Chain Security Architecture

```
Developer pushes code
    ↓
Cloud Build Pipeline:
    1. Build container image
    2. Trivy scan (fail on CRITICAL)
    3. Generate SBOM (CycloneDX)
    4. Cosign sign image (KMS key)
    5. Cosign attach SBOM attestation
    6. Push to Artifact Registry
    ↓
ArgoCD deploys to cluster
    ↓
Kyverno admission webhook:
    1. Verify image signature (cosign)
    2. Verify vulnerability attestation
    3. Check registry is approved
    4. Mutate to use image digest (pin)
    ↓
Pod runs (verified and attested)
```

## Key Concepts

- **Image signing**: Cryptographic proof that an image was built by your pipeline
- **Cosign**: Sigstore project tool for signing OCI artifacts
- **KMS signing**: Use cloud KMS for key management instead of local files
- **SBOM**: Software Bill of Materials — lists all dependencies in an image
- **Attestation**: Signed statement about an image (e.g., "this was scanned and has no critical vulns")
- **Admission control**: Kyverno verifies signatures at pod creation time
- **Image digest pinning**: `mutateDigest: true` replaces tags with immutable digests
- **Defense in depth**: Pipeline scanning + admission control + runtime monitoring

## Cleanup

```bash
kubectl delete clusterpolicy verify-image-signatures verify-vulnerability-scan
kubectl delete configmap cosign-pub-key -n kyverno
rm cosign.key cosign.pub /tmp/sbom.json /tmp/scan-report.json
```
