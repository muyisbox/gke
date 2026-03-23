# Task 1: Deploy Kyverno and Implement Cluster Governance Policies

**Level:** Advanced Operations

**Objective:** Deploy Kyverno as a policy engine, create policies that enforce image registry restrictions, resource limits, label requirements, and namespace isolation — then propagate governance across all SDLC environments.

## Context

Kyverno is a Kubernetes-native policy engine that validates, mutates, and generates resources. Unlike OPA/Gatekeeper (which uses Rego), Kyverno policies are written as Kubernetes resources in YAML. This makes it accessible to Kubernetes engineers without learning a new language.

In this platform, Kyverno will enforce governance across dev, staging, and gitops clusters via ArgoCD.

## Steps

### Part A: Deploy Kyverno to Dev via GitOps

1. Create the application definition. Create `gke-applications/dev/kyverno.yaml`:

   ```yaml
   name: kyverno
   chart: kyverno
   repoURL: https://kyverno.github.io/kyverno
   targetRevision: "3.3.4"
   namespace: kyverno
   cluster_env: dev
   helm:
     values:
       replicaCount: 2
       serviceMonitor:
         enabled: true
         labels:
           release: prometheus-monitoring
       admissionController:
         replicas: 2
         serviceAccount:
           annotations: {}
       backgroundController:
         replicas: 1
       cleanupController:
         replicas: 1
       reportsController:
         replicas: 1
       crds:
         install: true
       config:
         webhooks:
         - namespaceSelector:
             matchExpressions:
             - key: kubernetes.io/metadata.name
               operator: NotIn
               values:
               - kube-system
               - kyverno
   ```

   The `namespaceSelector` prevents Kyverno from blocking critical system namespaces.

2. Commit and merge via PR:

   ```bash
   git checkout -b feature/kyverno-governance
   git add gke-applications/dev/kyverno.yaml
   git commit -m "Deploy Kyverno policy engine to dev cluster"
   git push -u origin feature/kyverno-governance
   ```

3. After merge, verify on dev:

   ```bash
   kubectl get pods -n kyverno
   kubectl get crds | grep kyverno
   ```

   You should see CRDs: `clusterpolicies`, `policies`, `policyreports`, `clusteradmissionreports`, etc.

### Part B: Enforce Image Registry Restrictions

4. Create a ClusterPolicy that only allows images from Google Artifact Registry and trusted registries:

   ```yaml
   # policies/restrict-registries.yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: restrict-image-registries
     annotations:
       policies.kyverno.io/title: Restrict Image Registries
       policies.kyverno.io/category: Supply Chain Security
       policies.kyverno.io/severity: high
       policies.kyverno.io/description: >-
         Only allows container images from approved registries.
         This prevents pulling images from untrusted sources.
   spec:
     validationFailureAction: Enforce
     background: true
     rules:
     - name: validate-registries
       match:
         any:
         - resources:
             kinds:
             - Pod
       exclude:
         any:
         - resources:
             namespaces:
             - kube-system
             - kyverno
             - istio-system
             - istio-gateways
       validate:
         message: >-
           Images must come from approved registries:
           us-central1-docker.pkg.dev/cluster-dreams/,
           docker.io/library/, gcr.io/, or ghcr.io/.
           Found: {{ request.object.spec.containers[].image }}
         pattern:
           spec:
             containers:
             - image: "us-central1-docker.pkg.dev/cluster-dreams/* | docker.io/library/* | gcr.io/* | ghcr.io/* | registry.k8s.io/*"
   ```

5. Apply and test:

   ```bash
   kubectl apply -f policies/restrict-registries.yaml

   # This should SUCCEED (nginx is from docker.io/library):
   kubectl run test-allowed --image=docker.io/library/nginx:1.25 -n default --dry-run=server

   # This should FAIL (random registry):
   kubectl run test-denied --image=some-random-registry.io/evil-image:latest -n default --dry-run=server
   ```

6. Check the policy report:

   ```bash
   kubectl get policyreports -A
   kubectl get clusterpolicyreport -o yaml
   ```

### Part C: Require Resource Limits

7. Create a policy that requires all pods to have resource requests and limits:

   ```yaml
   # policies/require-resources.yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: require-resource-limits
     annotations:
       policies.kyverno.io/title: Require Resource Limits
       policies.kyverno.io/category: Resource Management
       policies.kyverno.io/severity: medium
   spec:
     validationFailureAction: Enforce
     background: true
     rules:
     - name: require-requests-and-limits
       match:
         any:
         - resources:
             kinds:
             - Pod
       exclude:
         any:
         - resources:
             namespaces:
             - kube-system
             - kyverno
             - istio-system
       validate:
         message: "All containers must have CPU and memory requests and limits defined."
         pattern:
           spec:
             containers:
             - resources:
                 requests:
                   memory: "?*"
                   cpu: "?*"
                 limits:
                   memory: "?*"
   ```

8. Test:

   ```bash
   # This should FAIL (no resources):
   kubectl run no-resources --image=nginx -n default --dry-run=server

   # This should SUCCEED:
   kubectl run with-resources --image=nginx -n default --dry-run=server \
     --overrides='{"spec":{"containers":[{"name":"with-resources","image":"nginx","resources":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"memory":"128Mi"}}}]}}'
   ```

### Part D: Require Labels on All Deployments

9. Create a policy that requires `app`, `team`, and `environment` labels:

   ```yaml
   # policies/require-labels.yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: require-labels
     annotations:
       policies.kyverno.io/title: Require Standard Labels
       policies.kyverno.io/category: Governance
       policies.kyverno.io/severity: medium
   spec:
     validationFailureAction: Audit
     background: true
     rules:
     - name: require-app-label
       match:
         any:
         - resources:
             kinds:
             - Deployment
             - StatefulSet
             - DaemonSet
       validate:
         message: "The label 'app.kubernetes.io/name' is required on all Deployments, StatefulSets, and DaemonSets."
         pattern:
           metadata:
             labels:
               app.kubernetes.io/name: "?*"
     - name: require-team-label
       match:
         any:
         - resources:
             kinds:
             - Deployment
             - StatefulSet
       validate:
         message: "The label 'team' is required to identify the owning team."
         pattern:
           metadata:
             labels:
               team: "?*"
   ```

   Note: `validationFailureAction: Audit` means violations are logged but not blocked. Use `Enforce` in staging/production.

10. Apply and check audit reports:

    ```bash
    kubectl apply -f policies/require-labels.yaml
    kubectl get policyreports -A
    kubectl get policyreport -n monitoring -o yaml | grep -A5 "result: fail"
    ```

### Part E: Mutate — Auto-Inject Labels

11. Create a mutation policy that automatically adds the `environment` label based on namespace:

    ```yaml
    # policies/mutate-env-label.yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: add-environment-label
      annotations:
        policies.kyverno.io/title: Auto-Add Environment Label
        policies.kyverno.io/category: Governance
    spec:
      rules:
      - name: add-env-label
        match:
          any:
          - resources:
              kinds:
              - Deployment
              - StatefulSet
              - Pod
        mutate:
          patchStrategicMerge:
            metadata:
              labels:
                +(environment): "dev"
    ```

    The `+()` prefix means "add only if not already set" — it won't overwrite existing labels.

12. Test the mutation:

    ```bash
    kubectl apply -f policies/mutate-env-label.yaml

    # Create a deployment and check the label was injected:
    kubectl create deployment test-mutate --image=nginx -n default --dry-run=server -o yaml | grep environment
    ```

### Part F: Generate — Auto-Create NetworkPolicies

13. Create a generate policy that creates a default deny NetworkPolicy whenever a new namespace is created:

    ```yaml
    # policies/generate-netpol.yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: generate-default-deny
      annotations:
        policies.kyverno.io/title: Generate Default Deny NetworkPolicy
        policies.kyverno.io/category: Network Security
    spec:
      rules:
      - name: generate-deny-all-ingress
        match:
          any:
          - resources:
              kinds:
              - Namespace
        exclude:
          any:
          - resources:
              names:
              - kube-system
              - kyverno
              - istio-system
        generate:
          apiVersion: networking.k8s.io/v1
          kind: NetworkPolicy
          name: default-deny-ingress
          namespace: "{{request.object.metadata.name}}"
          synchronize: true
          data:
            spec:
              podSelector: {}
              policyTypes:
              - Ingress
    ```

14. Test:

    ```bash
    kubectl apply -f policies/generate-netpol.yaml
    kubectl create namespace policy-test
    kubectl get networkpolicy -n policy-test
    # Should show default-deny-ingress was auto-created
    kubectl delete namespace policy-test
    ```

### Part G: Promote Kyverno Across SDLC

15. Copy `gke-applications/dev/kyverno.yaml` to staging and gitops:

    ```bash
    cp gke-applications/dev/kyverno.yaml gke-applications/staging/kyverno.yaml
    sed -i '' 's/cluster_env: dev/cluster_env: staging/' gke-applications/staging/kyverno.yaml

    cp gke-applications/dev/kyverno.yaml gke-applications/gitops/kyverno.yaml
    sed -i '' 's/cluster_env: dev/cluster_env: gitops/' gke-applications/gitops/kyverno.yaml
    ```

16. For policies, create a dedicated Helm chart or Git directory. Add a new ApplicationSet source or deploy policies as a separate ArgoCD application pointing to a `policies/` directory in the repo.

17. Change `validationFailureAction` per environment:
    - dev: `Audit` (log violations, don't block)
    - staging: `Enforce` (block violations, test before prod)
    - gitops: `Enforce` (hard enforcement)

### Part H: Monitor Policy Violations

18. Kyverno generates PolicyReports (a CRD). Query them:

    ```bash
    # Summary of violations
    kubectl get policyreports -A -o custom-columns=\
      NAMESPACE:.metadata.namespace,\
      PASS:.summary.pass,\
      FAIL:.summary.fail,\
      WARN:.summary.warn

    # Detailed failures
    kubectl get policyreport -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{range .results[?(@.result=="fail")]}{.policy}{"\t"}{.message}{"\n"}{end}{end}'
    ```

19. If Prometheus ServiceMonitor is enabled, query Kyverno metrics:

    ```promql
    # Policy violations by type
    kyverno_policy_results_total{rule_result="fail"}

    # Admission request latency
    histogram_quantile(0.99, rate(kyverno_admission_review_duration_seconds_bucket[5m]))
    ```

## Key Concepts

- **Validate**: Block or audit resources that don't meet policy
- **Mutate**: Automatically modify resources to add defaults
- **Generate**: Create companion resources when a trigger resource is created
- **Enforce vs Audit**: Enforce blocks creation; Audit logs but allows
- **PolicyReports**: Kubernetes-native audit trail of policy evaluations
- **Namespace exclusions**: Always exclude kube-system and the policy engine's own namespace
- **SDLC graduation**: Audit in dev → Enforce in staging → Enforce in production

## Cleanup

```bash
kubectl delete clusterpolicy --all
kubectl delete -f policies/
rm -rf policies/
```
