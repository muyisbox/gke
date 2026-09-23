data "google_client_config" "default" {}

# The hub's own cluster, read back after creation so ArgoCD can register it.
data "google_container_cluster" "gitops" {
  count    = local.is_gitops ? 1 : 0
  name     = local.gitops_cluster_name
  location = var.region
  project  = var.project_id

  depends_on = [module.gke]
}

# Which clusters exist right now. Spokes are destroyed nightly for cost, so
# looking them up unconditionally would fail every plan during that window.
data "http" "gke_clusters" {
  count = local.is_gitops ? 1 : 0
  url   = "https://container.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/clusters"

  request_headers = {
    Authorization = "Bearer ${data.google_client_config.default.access_token}"
  }
}

data "google_container_cluster" "remote" {
  for_each = local.reachable_spokes

  name     = "${each.key}-cluster"
  location = var.region
  project  = var.project_id
}
