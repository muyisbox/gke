module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "~> 45.0"

  project_id = var.project_id
  name       = local.cluster_name
  region     = var.region
  zones      = var.zones

  network           = local.shared_network_name
  subnetwork        = local.subnet_name
  ip_range_pods     = "${local.env}-pods"
  ip_range_services = "${local.env}-services"

  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = local.master_ipv4_cidr_block

  release_channel            = var.release_channel
  deletion_protection        = false
  http_load_balancing        = false
  network_policy             = true
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false

  # Capacity comes entirely from node auto-provisioning; no static pools.
  cluster_autoscaling = var.cluster_autoscaling
  node_pools          = []

  node_pools_oauth_scopes = { all = var.node_oauth_scopes }
  node_pools_labels       = { all = {} }
  node_pools_metadata     = { all = {} }
  node_pools_taints       = { all = [] }
  node_pools_tags         = { all = [] }
}

# Cloud Build's Terraform identity needs container.admin to manage in-cluster
# resources, but only on the cluster this workspace owns.
resource "google_project_iam_member" "terraform_cluster_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${var.terraform_service_account}"

  condition {
    title       = "${local.env}-cluster-admin"
    description = "Scoped to ${local.cluster_name} only"
    expression = join(" || ", [
      "resource.name == \"projects/${var.project_id}/locations/${var.region}/clusters/${local.cluster_name}\"",
      "resource.name.startsWith(\"projects/${var.project_id}/locations/${var.region}/clusters/${local.cluster_name}/\")",
    ])
  }
}

# Terraform workspaces and var.environments keys must line up. Without this the
# failure is an "Invalid index" deep inside a local — most often from running in
# the default workspace instead of selecting one.
resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = contains(keys(var.environments), terraform.workspace)
      error_message = "Workspace ${terraform.workspace} has no entry in var.environments (known: ${join(", ", keys(var.environments))}). Run: terraform workspace select <env>"
    }
  }
}
