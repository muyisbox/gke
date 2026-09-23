# ============================================================
# External Secrets Operator — GCP side
#
# ESO runs on the gitops cluster and turns Secret Manager entries into ArgoCD
# cluster Secrets. This keeps spoke CA certificates out of Terraform state and
# lets spokes re-register themselves after the nightly destroy/recreate cycle
# without a Terraform run.
#
# Ownership split: ArgoCD owns the ESO chart, its CRDs, and the
# ClusterSecretStore (declared as extraObjects in the app definition).
# Terraform owns only the GCP side plus the per-spoke ExternalSecrets, which
# are derived from the live cluster list and so cannot live in a static file.
#
# Terraform must not apply the CRDs. The chart always creates the core ones, so
# both would be server-side-apply managers of .spec.versions and would conflict
# the moment the two sides disagreed on a version.
# ============================================================

locals {
  eso_namespace       = "external-secrets"
  eso_service_account = "external-secrets"
}

resource "google_service_account" "eso" {
  count        = local.is_gitops ? 1 : 0
  account_id   = "eso-controller"
  display_name = "ESO Controller - Workload Identity"
  project      = var.project_id
}

resource "google_project_iam_member" "eso_secret_accessor" {
  count   = local.is_gitops ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso[0].email}"
}

resource "google_service_account_iam_member" "eso_workload_identity" {
  count              = local.is_gitops ? 1 : 0
  service_account_id = google_service_account.eso[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${local.eso_namespace}/${local.eso_service_account}]"
}

# ------------------------------------------------------------
# Secret Manager: one entry per spoke cluster
# ------------------------------------------------------------

resource "google_secret_manager_secret" "argocd_cluster" {
  for_each  = local.eso_managed_clusters
  secret_id = "argocd-cluster-${each.key}"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = {
    managed-by = "terraform"
    purpose    = "argocd-cluster-secret"
  }
}

resource "google_secret_manager_secret_version" "argocd_cluster" {
  for_each = local.eso_managed_clusters
  secret   = google_secret_manager_secret.argocd_cluster[each.key].id

  secret_data = jsonencode({
    name     = each.value.name
    endpoint = each.value.endpoint
    ca_cert  = each.value.ca_cert
  })
}

# ------------------------------------------------------------
# In-cluster ESO objects
# ------------------------------------------------------------

# One ExternalSecret per spoke; ESO materialises it as an ArgoCD cluster Secret.
resource "kubectl_manifest" "argocd_external_secret" {
  for_each          = local.eso_managed_clusters
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "${each.key}-cluster-secret"
      namespace = var.argocd.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "gcp-secret-manager"
        kind = "ClusterSecretStore"
      }
      target = {
        name = "${each.key}-cluster-secret"
        template = {
          engineVersion = "v2"
          metadata = {
            labels = {
              "argocd.argoproj.io/secret-type" = "cluster"
            }
          }
          data = {
            name   = "{{ .name }}"
            server = "https://{{ .endpoint }}"
            config = jsonencode({
              execProviderConfig = {
                command    = "argocd-k8s-auth"
                args       = ["gcp"]
                apiVersion = "client.authentication.k8s.io/v1beta1"
              }
              tlsClientConfig = {
                insecure = false
                caData   = "{{ .ca_cert }}"
              }
            })
          }
        }
      }
      dataFrom = [{
        extract = { key = "argocd-cluster-${each.key}" }
      }]
    }
  })

  depends_on = [module.argocd]
}
