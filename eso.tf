# ============================================================
# External Secrets Operator — GCP side
#
# ESO runs on the gitops cluster and turns Secret Manager entries into ArgoCD
# cluster Secrets. This keeps spoke CA certificates out of Terraform state and
# lets spokes re-register themselves after the nightly destroy/recreate cycle
# without a Terraform run.
# ============================================================

locals {
  eso_namespace       = "external-secrets"
  eso_service_account = "external-secrets"

  # Pinned to var.eso_version so the CRDs Terraform applies stay in lockstep
  # with the chart ArgoCD deploys.
  eso_crds = {
    clustersecretstores = "external-secrets.io_clustersecretstores"
    externalsecrets     = "external-secrets.io_externalsecrets"
  }
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

# Only the two CRDs we actually use. The chart can install the full set, but
# Terraform needs these to exist before it can create the CRs below.
data "http" "eso_crd" {
  for_each = local.is_gitops ? local.eso_crds : {}
  url      = "https://raw.githubusercontent.com/external-secrets/external-secrets/v${var.eso_version}/config/crds/bases/${each.value}.yaml"
}

resource "kubectl_manifest" "eso_crd" {
  for_each = local.is_gitops ? local.eso_crds : {}

  yaml_body         = data.http.eso_crd[each.key].response_body
  server_side_apply = true

  depends_on = [module.gke]
}

resource "kubectl_manifest" "eso_cluster_secret_store" {
  count             = local.is_gitops ? 1 : 0
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "gcp-secret-manager" }
    spec = {
      provider = {
        gcpsm = {
          projectID = var.project_id
          auth = {
            workloadIdentity = {
              clusterLocation  = var.region
              clusterName      = local.gitops_cluster_name
              clusterProjectID = var.project_id
              serviceAccountRef = {
                name      = local.eso_service_account
                namespace = local.eso_namespace
              }
            }
          }
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.eso_crd,
    module.argocd,
  ]
}

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

  depends_on = [kubectl_manifest.eso_cluster_secret_store]
}
