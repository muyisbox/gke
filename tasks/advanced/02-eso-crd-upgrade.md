# Task 2: Upgrade External Secrets Operator with CRD Handling

**Level:** Advanced

**Objective:** Upgrade ESO across all clusters, handling CRD compatibility, Terraform state, and the Helm chart deployment via ArgoCD.

## Context

ESO has two installation layers in this platform:
1. **Terraform** (`eso.tf`): Installs CRDs and creates ClusterSecretStore on the gitops cluster
2. **ArgoCD** (`gke-applications/*/external-secrets.yaml`): Deploys the ESO operator Helm chart per cluster

Both must be upgraded in sync. CRD version mismatches can break secret syncing.

## Steps

### Part A: Understand the Current Setup

1. Check the current ESO version:

   ```bash
   grep eso_version values.auto.tfvars
   grep targetRevision gke-applications/*/external-secrets.yaml
   ```

   Both should show `2.1.0`.

2. Open `eso.tf` and trace the CRD installation:
   - CRDs are downloaded from GitHub: `https://raw.githubusercontent.com/external-secrets/external-secrets/v${var.eso_version}/deploy/crds/...`
   - They're applied via `kubectl_manifest` with server-side apply
   - Only created in the gitops workspace

3. Check running CRD versions:

   ```bash
   kubectl get crds | grep external-secrets
   kubectl get crd externalsecrets.external-secrets.io -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}'
   ```

### Part B: Plan the Upgrade

4. Check the ESO changelog for breaking changes between versions:
   - Are there CRD schema changes?
   - Are there API version changes (v1beta1 → v1)?
   - Are there new required fields?

5. Create a branch:

   ```bash
   git checkout -b upgrade/eso-2.2.0
   ```

### Part C: Upgrade CRDs First (Terraform)

6. Update `values.auto.tfvars`:

   ```hcl
   eso_version = "2.2.0"
   ```

7. Plan for the gitops workspace:

   ```bash
   terraform workspace select gitops
   terraform plan
   ```

8. Review the plan:
   - Do the `kubectl_manifest` resources show as needing update?
   - Is the ClusterSecretStore being recreated or updated in-place?
   - Are there any destructive changes?

9. **Apply (if validated)**:

   ```bash
   terraform apply
   ```

   Watch for:
   - CRD update success
   - ClusterSecretStore stays healthy
   - ExternalSecrets continue syncing

10. Verify CRDs are updated:

    ```bash
    kubectl get crds externalsecrets.external-secrets.io -o jsonpath='{.spec.versions[*].name}'
    ```

### Part D: Upgrade the Helm Chart (ArgoCD)

11. Update `gke-applications/dev/external-secrets.yaml`:

    ```yaml
    targetRevision: "2.2.0"  # Was 2.1.0
    ```

12. Commit, push, merge. Watch ArgoCD sync:

    ```bash
    kubectl get applications -n argocd --context=gitops | grep external-secrets
    ```

13. Verify ESO pods are running the new version on dev:

    ```bash
    kubectl get pods -n external-secrets --context=dev -o jsonpath='{.items[*].spec.containers[0].image}'
    ```

14. Verify secrets are still syncing:

    ```bash
    kubectl get externalsecrets -A --context=dev
    ```

### Part E: Promote Through SDLC

15. After validating dev, update staging:

    ```bash
    sed -i '' 's/2.1.0/2.2.0/' gke-applications/staging/external-secrets.yaml
    ```

16. Commit, merge, validate. Then update gitops.

### Part F: Handle CRD Conflicts

17. Common issue: If the Helm chart's CRDs conflict with the Terraform-installed CRDs:

    ```bash
    # Check CRD ownership
    kubectl get crd externalsecrets.external-secrets.io -o jsonpath='{.metadata.annotations}'
    ```

    The CRDs installed by Terraform won't have Helm ownership annotations. The Helm chart has `installCRDs: true`, which can conflict. Solutions:
    - Set `installCRDs: false` in the Helm values (let Terraform own CRDs)
    - Or let Helm manage CRDs and remove the Terraform `kubectl_manifest` resources

## Key Concepts

- **Dual CRD management**: Terraform installs CRDs on gitops; Helm chart can also install CRDs per cluster
- **CRD-first**: Always upgrade CRDs before the operator that uses them
- **Version sync**: `eso_version` in Terraform must match `targetRevision` in app YAML
- **CRD ownership conflicts**: Only one system should own CRDs — either Terraform or Helm, not both
- **Validation**: Always verify ExternalSecrets sync status after upgrade

## Rollback Plan

1. Revert `eso_version` to `2.1.0` in `values.auto.tfvars`
2. Revert `targetRevision` to `2.1.0` in app YAMLs
3. Run `terraform apply` for gitops workspace
4. Merge reverted YAMLs — ArgoCD rolls back the Helm chart
