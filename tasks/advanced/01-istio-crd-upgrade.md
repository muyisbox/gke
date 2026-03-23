# Task 1: Upgrade Istio Across All Clusters (CRD-Aware Process)

**Level:** Advanced

**Objective:** Perform a controlled Istio upgrade from 1.29.x to a newer version across all clusters, handling CRDs, revision-based canary upgrades, and SDLC promotion.

## Context

Istio is deployed as 3 components per cluster: `istio-base` (CRDs), `istiod` (control plane), `istio-gateway` (data plane). Upgrades must follow a specific order and use revision-based canary deployments.

## Upgrade Order (Critical)

```
1. istio-base (CRDs) → 2. istiod (control plane) → 3. istio-gateway (data plane)
```

CRDs must be upgraded FIRST. If you upgrade istiod before the CRDs, it may use API fields that don't exist yet.

## Steps

### Part A: Pre-Upgrade Checks

1. Document current versions across all clusters:

   ```bash
   for ctx in dev staging gitops; do
     echo "=== $ctx ==="
     kubectl get pods -n istio-system --context=$ctx -l app=istiod -o jsonpath='{.items[0].spec.containers[0].image}'
     echo
   done
   ```

2. Check the current revision tag in all istiod configs:

   ```bash
   grep -r "revision:" gke-applications/*/istiod.yaml
   ```

   Currently: `"1-29"` across all environments.

3. Check if any workloads are pinned to the current revision:

   ```bash
   kubectl get ns --show-labels | grep istio
   kubectl get pods -A -l istio.io/rev=1-29
   ```

### Part B: Upgrade Dev First

4. Create a branch:

   ```bash
   git checkout -b upgrade/istio-1.30
   ```

5. Update `gke-applications/dev/istio-base.yaml`:
   - Change `targetRevision: "1.29.*"` to `targetRevision: "1.30.*"`

6. Update `gke-applications/dev/istiod.yaml`:
   - Change `targetRevision: "1.29.*"` to `targetRevision: "1.30.*"`
   - Change `revision: "1-29"` to `revision: "1-30"`
   - Keep `revisionTags: [stable]` — this lets existing workloads migrate

7. Update `gke-applications/dev/istio-gateway.yaml`:
   - Change `targetRevision: "1.29.*"` to `targetRevision: "1.30.*"`
   - Change `revision: "1-29"` to `revision: "1-30"`

8. Commit and push:

   ```bash
   git add gke-applications/dev/istio-*.yaml gke-applications/dev/istiod.yaml
   git commit -m "Upgrade Istio to 1.30 in dev environment"
   git push -u origin upgrade/istio-1.30
   ```

### Part C: Validate the Dev Upgrade

9. After merge, verify on dev cluster:

   ```bash
   # Check istiod version
   kubectl get pods -n istio-system -l app=istiod --context=dev -o jsonpath='{.items[*].spec.containers[0].image}'

   # Check CRDs are updated
   kubectl get crds -l app=istiod --context=dev

   # Check the revision
   kubectl get pods -n istio-system --context=dev -l app=istiod -o jsonpath='{.items[0].metadata.labels.istio\.io/rev}'

   # Check gateways are on the new version
   kubectl get pods -n istio-gateways --context=dev -o jsonpath='{.items[*].spec.containers[0].image}'
   ```

10. Verify workloads are healthy:

    ```bash
    # Check bookinfo pods have new sidecar
    kubectl get pods -n bookinfo --context=dev

    # Restart a workload to pick up the new sidecar
    kubectl rollout restart deployment productpage-v1 -n bookinfo --context=dev

    # Verify sidecar version
    kubectl get pods -n bookinfo --context=dev -o jsonpath='{.items[0].spec.containers[?(@.name=="istio-proxy")].image}'
    ```

11. Check Kiali for any errors in the mesh.

### Part D: Promote to Staging

12. After validating dev, update staging files with the same changes:

    ```bash
    # Update staging files
    sed -i '' 's/1.29.\*/1.30.*/g' gke-applications/staging/istio-base.yaml gke-applications/staging/istiod.yaml gke-applications/staging/istio-gateway.yaml
    sed -i '' 's/1-29/1-30/g' gke-applications/staging/istiod.yaml gke-applications/staging/istio-gateway.yaml
    ```

13. Commit, push, PR, merge. Validate on staging.

### Part E: Promote to Gitops

14. Repeat for gitops. This is the most critical environment:
    - Update all three files
    - PR review should be thorough
    - Validate ArgoCD is still managing all clusters after the upgrade

### Part F: Post-Upgrade Cleanup

15. Verify all clusters are on the same version:

    ```bash
    for ctx in dev staging gitops; do
      echo "=== $ctx ==="
      kubectl get pods -n istio-system --context=$ctx -l app=istiod -o jsonpath='{.items[0].spec.containers[0].image}'
      echo
    done
    ```

16. Check for any old revision pods still running:

    ```bash
    kubectl get pods -A -l istio.io/rev=1-29
    ```

    If any exist, restart those deployments to pick up the new sidecar.

## Key Concepts

- **CRD-first upgrades**: Always update CRDs before the components that use them
- **Revision-based canary**: The `revision` field allows running two control planes side-by-side during migration
- **revisionTags**: The `stable` tag is an alias that lets workloads reference a logical name instead of a specific revision
- **SDLC order**: Always upgrade dev → staging → gitops with validation at each step
- **Sidecar refresh**: Existing pods keep old sidecars until restarted

## Rollback Plan

If issues are found after upgrading dev:
1. Revert the YAML files to `1.29.*` and `1-29`
2. Commit and merge — ArgoCD will rollback automatically
3. Restart affected workloads to get old sidecars back
