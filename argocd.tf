
## This installs argo into the gitops cluster only
module "argocd" {
  source   = "./modules/helm"
  for_each = terraform.workspace == "gitops" ? toset(["gitops"]) : toset([])

  namespace  = lookup(local.charts.argocd, "namespace", "default")
  repository = "https://argoproj.github.io/argo-helm"
  app        = lookup(local.charts.argocd, "app", null)
  values     = lookup(local.charts.argocd, "values", [])

  depends_on = [
    module.gke
  ]

}

# ArgoCD apps - deployed only on gitops cluster
module "argocd-apps" {
  source     = "./modules/helm"
  for_each   = terraform.workspace == "gitops" ? toset(["gitops"]) : toset([])
  namespace  = lookup(local.charts.argocd_apps, "namespace", "default")
  repository = "https://argoproj.github.io/argo-helm"
  app        = lookup(local.charts.argocd_apps, "app")
  values     = lookup(local.charts.argocd_apps, "values", [])
  depends_on = [
    module.argocd, module.gke
  ]
}

# GCP Service Account for ArgoCD Workload Identity
resource "google_service_account" "argocd" {
  count        = terraform.workspace == "gitops" ? 1 : 0
  account_id   = "argocd-controller"
  display_name = "ArgoCD Controller - Workload Identity"
  project      = var.project_id
}

# Grant container.developer so ArgoCD can manage resources on all clusters
resource "google_project_iam_member" "argocd_container_developer" {
  count   = terraform.workspace == "gitops" ? 1 : 0
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.argocd[0].email}"
}

# Workload Identity binding: argocd-application-controller K8s SA -> GCP SA
resource "google_service_account_iam_member" "argocd_controller_wi" {
  count              = terraform.workspace == "gitops" ? 1 : 0
  service_account_id = google_service_account.argocd[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-application-controller]"
}

# Workload Identity binding: argocd-server K8s SA -> GCP SA
resource "google_service_account_iam_member" "argocd_server_wi" {
  count              = terraform.workspace == "gitops" ? 1 : 0
  service_account_id = google_service_account.argocd[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[argocd/argocd-server]"
}

# Data sources for all cluster endpoints (used to register clusters in ArgoCD)
data "google_container_cluster" "gitops" {
  count    = terraform.workspace == "gitops" ? 1 : 0
  name     = "gitops-cluster"
  location = var.region
  project  = var.project_id

  depends_on = [module.gke]
}

data "google_container_cluster" "dev" {
  count    = terraform.workspace == "gitops" ? 1 : 0
  name     = "dev-cluster"
  location = var.region
  project  = var.project_id
}

data "google_container_cluster" "staging" {
  count    = terraform.workspace == "gitops" ? 1 : 0
  name     = "staging-cluster"
  location = var.region
  project  = var.project_id
}

# ArgoCD cluster secrets - register all 3 clusters via Workload Identity
resource "kubernetes_secret" "argocd_cluster" {
  for_each = local.argocd_clusters

  metadata {
    name      = "${each.key}-cluster-secret"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }

  data = {
    name   = "${each.key}-cluster"
    server = "https://${each.value.endpoint}"
    config = jsonencode({
      execProviderConfig = {
        command    = "argocd-k8s-auth"
        args       = ["gcp"]
        apiVersion = "client.authentication.k8s.io/v1beta1"
      }
      tlsClientConfig = {
        insecure = false
        caData   = each.value.ca_cert
      }
    })
  }

  depends_on = [module.argocd]
}
