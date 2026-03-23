# Task 5: Kyverno Advanced — Multi-Tenant Policies, Resource Quotas, and Policy Exceptions

**Level:** Advanced Operations

**Objective:** Implement advanced Kyverno policies for multi-tenancy: enforce resource quotas per namespace, restrict privilege escalation, mandate pod security standards, and handle policy exceptions for platform components.

## Context

In a shared GKE cluster, different teams deploy workloads side-by-side. Governance ensures one team can't consume all resources, run privileged containers, or bypass security controls. Platform components (Istio, ArgoCD, monitoring) need exceptions since they require elevated permissions.

## Steps

### Part A: Pod Security Standards (Baseline)

1. Create a policy that enforces the Kubernetes Pod Security Standard "Baseline" profile:

   ```yaml
   # policies/pod-security-baseline.yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: pod-security-baseline
     annotations:
       policies.kyverno.io/title: Pod Security Standards - Baseline
       policies.kyverno.io/category: Pod Security
       policies.kyverno.io/severity: high
       policies.kyverno.io/description: >-
         Enforces the baseline Pod Security Standard.
         Prevents privilege escalation, host namespaces, and dangerous capabilities.
   spec:
     validationFailureAction: Enforce
     background: true
     rules:
     - name: deny-privileged-containers
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
             - istio-system
             - kyverno
             - monitoring
       validate:
         message: "Privileged containers are not allowed."
         pattern:
           spec:
             containers:
             - =(securityContext):
                 =(privileged): false
     - name: deny-host-namespaces
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
             - istio-system
             - monitoring
       validate:
         message: "Host namespaces (hostNetwork, hostPID, hostIPC) are not allowed."
         pattern:
           spec:
             =(hostNetwork): false
             =(hostPID): false
             =(hostIPC): false
     - name: restrict-capabilities
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
             - istio-system
       validate:
         message: "Adding capabilities beyond the baseline set is not allowed. Drop ALL and add only NET_BIND_SERVICE if needed."
         deny:
           conditions:
             any:
             - key: "{{ request.object.spec.containers[].securityContext.capabilities.add[] || '' }}"
               operator: AnyNotIn
               value:
               - ""
               - NET_BIND_SERVICE
   ```

2. Apply and test:

   ```bash
   kubectl apply -f policies/pod-security-baseline.yaml

   # This should FAIL:
   kubectl run privileged-test --image=nginx -n default --dry-run=server \
     --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}'

   # This should SUCCEED:
   kubectl run safe-test --image=nginx -n default --dry-run=server \
     --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":false,"runAsNonRoot":true,"runAsUser":1000}}]}}'
   ```

### Part B: Auto-Generate ResourceQuotas for New Namespaces

3. Create a Kyverno generate policy that creates ResourceQuotas and LimitRanges for every new namespace:

   ```yaml
   # policies/generate-quotas.yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: generate-resource-quotas
     annotations:
       policies.kyverno.io/title: Generate Resource Quotas
       policies.kyverno.io/category: Resource Management
       policies.kyverno.io/description: >-
         Automatically creates ResourceQuotas and LimitRanges
         when a new namespace is created, preventing resource exhaustion.
   spec:
     rules:
     - name: generate-quota
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
             - kube-public
             - kube-node-lease
             - kyverno
             - istio-system
             - istio-gateways
             - argocd
             - monitoring
             - logging
       generate:
         apiVersion: v1
         kind: ResourceQuota
         name: default-quota
         namespace: "{{request.object.metadata.name}}"
         synchronize: true
         data:
           spec:
             hard:
               requests.cpu: "4"
               requests.memory: 8Gi
               limits.cpu: "8"
               limits.memory: 16Gi
               pods: "50"
               services: "20"
               persistentvolumeclaims: "10"
     - name: generate-limit-range
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
             - kube-public
             - kube-node-lease
             - kyverno
             - istio-system
             - istio-gateways
             - argocd
             - monitoring
             - logging
       generate:
         apiVersion: v1
         kind: LimitRange
         name: default-limits
         namespace: "{{request.object.metadata.name}}"
         synchronize: true
         data:
           spec:
             limits:
             - default:
                 cpu: 500m
                 memory: 512Mi
               defaultRequest:
                 cpu: 100m
                 memory: 128Mi
               type: Container
   ```

4. Test by creating a new namespace:

   ```bash
   kubectl apply -f policies/generate-quotas.yaml
   kubectl create namespace team-alpha

   # Verify quotas were auto-created:
   kubectl get resourcequota -n team-alpha
   kubectl get limitrange -n team-alpha
   kubectl describe resourcequota default-quota -n team-alpha
   ```

5. Test that limits are enforced:

   ```bash
   # This gets default limits from LimitRange automatically:
   kubectl run test --image=nginx -n team-alpha
   kubectl describe pod test -n team-alpha | grep -A4 "Limits\|Requests"

   kubectl delete namespace team-alpha
   ```

### Part C: Policy Exceptions for Platform Components

6. Platform components like Istio init containers need `NET_ADMIN` capability. Create a PolicyException:

   ```yaml
   # policies/exception-istio.yaml
   apiVersion: kyverno.io/v2
   kind: PolicyException
   metadata:
     name: istio-system-exception
     namespace: kyverno
   spec:
     exceptions:
     - policyName: pod-security-baseline
       ruleNames:
       - restrict-capabilities
       - deny-privileged-containers
     match:
       any:
       - resources:
           kinds:
           - Pod
           namespaces:
           - istio-system
           - istio-gateways
           - bookinfo
   ```

7. Apply and verify:

   ```bash
   kubectl apply -f policies/exception-istio.yaml

   # Istio pods should be allowed their capabilities
   kubectl get pods -n istio-system  # Should be running
   ```

### Part D: Prevent Latest Tag Usage

8. Create a policy that blocks the `:latest` tag and requires explicit tags or digests:

   ```yaml
   # policies/disallow-latest-tag.yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: disallow-latest-tag
     annotations:
       policies.kyverno.io/title: Disallow Latest Tag
       policies.kyverno.io/category: Supply Chain Security
       policies.kyverno.io/severity: medium
   spec:
     validationFailureAction: Enforce
     background: true
     rules:
     - name: validate-image-tag
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
       validate:
         message: >-
           Using the ':latest' tag is not allowed. Images must use explicit version tags
           (e.g., nginx:1.25) or digests (e.g., nginx@sha256:abc123...).
         pattern:
           spec:
             containers:
             - image: "*:*"
     - name: block-latest-explicitly
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
       validate:
         message: "The ':latest' tag is not allowed. Use a specific version tag."
         pattern:
           spec:
             containers:
             - image: "!*:latest"
   ```

9. Test:

   ```bash
   kubectl apply -f policies/disallow-latest-tag.yaml

   # FAIL:
   kubectl run test --image=nginx:latest -n default --dry-run=server
   kubectl run test --image=nginx -n default --dry-run=server  # Implicit latest

   # SUCCEED:
   kubectl run test --image=nginx:1.25 -n default --dry-run=server
   ```

### Part E: Enforce Istio Sidecar Injection

10. Create a policy that ensures all application namespaces have Istio injection enabled:

    ```yaml
    # policies/require-istio-injection.yaml
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-istio-injection
      annotations:
        policies.kyverno.io/title: Require Istio Sidecar Injection
        policies.kyverno.io/category: Service Mesh
    spec:
      validationFailureAction: Audit
      rules:
      - name: require-injection-label
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
              - kube-public
              - kube-node-lease
              - kyverno
              - vpa
              - argo-rollouts
        validate:
          message: >-
            All application namespaces must have the label
            'istio-injection=enabled' or 'istio.io/revy=stable'
            to ensure Istio sidecar injection.
          anyPattern:
          - metadata:
              labels:
                istio-injection: enabled
          - metadata:
              labels:
                istio.io/revy: stable
    ```

### Part F: Policy Dashboard in Grafana

11. Create a Grafana dashboard panel for Kyverno metrics:

    ```promql
    # Policy violation rate
    sum(rate(kyverno_policy_results_total{rule_result="fail"}[5m])) by (policy_name)

    # Top violated policies
    topk(5, sum(kyverno_policy_results_total{rule_result="fail"}) by (policy_name))

    # Admission webhook latency
    histogram_quantile(0.95, sum(rate(kyverno_admission_review_duration_seconds_bucket[5m])) by (le))
    ```

12. Set up an alert for high violation rates:

    ```promql
    sum(rate(kyverno_policy_results_total{rule_result="fail", rule_execution_cause="admission"}[5m])) > 0.5
    ```

### Part G: SDLC Policy Propagation

13. Organize policies by enforcement level:

    ```
    policies/
    ├── common/               # Applied to all environments
    │   ├── disallow-latest-tag.yaml
    │   └── require-labels.yaml
    ├── dev/                  # Audit mode
    │   └── kustomization.yaml  (patches validationFailureAction to Audit)
    ├── staging/              # Enforce mode
    │   └── kustomization.yaml  (patches validationFailureAction to Enforce)
    └── gitops/               # Enforce mode + stricter rules
        └── kustomization.yaml
    ```

14. Deploy policies as an ArgoCD application per cluster, pointing to the appropriate overlay directory.

## Key Concepts

- **Pod Security Standards**: Kubernetes-defined security profiles (Privileged, Baseline, Restricted)
- **Generate policies**: Auto-create companion resources (quotas, network policies)
- **PolicyExceptions**: Allow platform components to bypass specific rules
- **Multi-tenancy**: ResourceQuotas + LimitRanges prevent resource exhaustion
- **`:latest` ban**: Forces teams to use explicit, traceable image versions
- **SDLC graduation**: Audit in dev → Enforce in staging/prod
- **Synchronize: true**: Kyverno keeps generated resources in sync (deleting them recreates them)

## Cleanup

```bash
kubectl delete clusterpolicy --all
kubectl delete policyexception --all -n kyverno
```
