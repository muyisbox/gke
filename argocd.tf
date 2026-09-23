# ============================================================
# ArgoCD — installed on the gitops cluster only
# ============================================================

locals {
  gitops_only = local.is_gitops ? toset([var.gitops_workspace]) : toset([])
}

module "argocd" {
  source   = "./modules/helm"
  for_each = local.gitops_only

  namespace  = local.charts.argocd.namespace
  repository = "https://argoproj.github.io/argo-helm"
  app        = local.charts.argocd.app
  values     = local.charts.argocd.values

  depends_on = [module.gke]
}

# Renders the per-cluster AppProjects and ApplicationSets that pull
# gke-applications/<env>/*.yaml out of the config repo.
module "argocd-apps" {
  source   = "./modules/helm"
  for_each = local.gitops_only

  namespace  = local.charts.argocd_apps.namespace
  repository = "https://argoproj.github.io/argo-helm"
  app        = local.charts.argocd_apps.app
  values     = local.charts.argocd_apps.values

  depends_on = [module.argocd]
}

# ------------------------------------------------------------
# Workload Identity for the ArgoCD control plane
# ------------------------------------------------------------

resource "google_service_account" "argocd" {
  count        = local.is_gitops ? 1 : 0
  account_id   = "argocd-controller"
  display_name = "ArgoCD Controller - Workload Identity"
  project      = var.project_id
}

# container.admin, not container.developer: the hub-spoke pattern has ArgoCD
# creating CRDs, namespaces and ClusterRoles on every spoke.
resource "google_project_iam_member" "argocd_container_admin" {
  count   = local.is_gitops ? 1 : 0
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.argocd[0].email}"
}

resource "google_service_account_iam_member" "argocd_workload_identity" {
  for_each = local.is_gitops ? toset(["argocd-application-controller", "argocd-server"]) : toset([])

  service_account_id = google_service_account.argocd[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.argocd.namespace}/${each.key}]"
}

# ------------------------------------------------------------
# Cluster registration
# ------------------------------------------------------------

# The hub registers itself directly. Spokes are registered by ESO from Secret
# Manager (see eso.tf) so their CA data never lands in Terraform state.
resource "kubernetes_secret_v1" "argocd_cluster" {
  for_each = local.gitops_only

  metadata {
    name      = "${each.key}-cluster-secret"
    namespace = var.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }

  data = {
    name   = local.argocd_clusters[each.key].name
    server = "https://${local.argocd_clusters[each.key].endpoint}"
    config = jsonencode({
      execProviderConfig = {
        command    = "argocd-k8s-auth"
        args       = ["gcp"]
        apiVersion = "client.authentication.k8s.io/v1beta1"
      }
      tlsClientConfig = {
        insecure = false
        caData   = local.argocd_clusters[each.key].ca_cert
      }
    })
  }

  depends_on = [module.argocd]
}
