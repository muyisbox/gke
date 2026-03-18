# ============================================================
# External Secrets Operator - GCP Infrastructure
# ============================================================

# GCP Service Account for ESO Workload Identity
resource "google_service_account" "eso" {
  count        = terraform.workspace == "gitops" ? 1 : 0
  account_id   = "eso-controller"
  display_name = "ESO Controller - Workload Identity"
  project      = var.project_id
}

# Grant ESO SA access to read secrets from Secret Manager
resource "google_project_iam_member" "eso_secret_accessor" {
  count   = terraform.workspace == "gitops" ? 1 : 0
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso[0].email}"
}

# Workload Identity binding: external-secrets K8s SA -> GCP SA
resource "google_service_account_iam_member" "eso_wi" {
  count              = terraform.workspace == "gitops" ? 1 : 0
  service_account_id = google_service_account.eso[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}

# Secret Manager: one secret per remote cluster (dev, staging)
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
    name     = "${each.key}-cluster"
    endpoint = each.value.endpoint
    ca_cert  = each.value.ca_cert
  })
}

# ClusterSecretStore: ESO backend pointing to GCP Secret Manager via WI
resource "kubernetes_manifest" "eso_cluster_secret_store" {
  count = terraform.workspace == "gitops" ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "gcp-secret-manager"
    }
    spec = {
      provider = {
        gcpsm = {
          projectID = var.project_id
          auth = {
            workloadIdentity = {
              clusterLocation  = var.region
              clusterName      = "gitops-cluster"
              clusterProjectID = var.project_id
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [module.argocd]
}

# ExternalSecrets: one per remote cluster, creates ArgoCD cluster secrets
resource "kubernetes_manifest" "argocd_external_secret" {
  for_each = local.eso_managed_clusters

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "${each.key}-cluster-secret"
      namespace = "argocd"
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
            config = <<-EOT
              {"execProviderConfig":{"command":"argocd-k8s-auth","args":["gcp"],"apiVersion":"client.authentication.k8s.io/v1beta1"},"tlsClientConfig":{"insecure":false,"caData":"{{ .ca_cert }}"}}
            EOT
          }
        }
      }
      dataFrom = [{
        extract = {
          key = "argocd-cluster-${each.key}"
        }
      }]
    }
  }

  depends_on = [kubernetes_manifest.eso_cluster_secret_store]
}
