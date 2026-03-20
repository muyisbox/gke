# Shared Network Infrastructure
# GitOps workspace creates and manages the shared network
# Dev and Staging workspaces reference it via data source

# Shared VPC Network (created only in gitops workspace)
module "shared-network" {
  count = terraform.workspace == "gitops" ? 1 : 0

  source  = "terraform-google-modules/network/google"
  version = ">= 4.0.1"

  project_id   = var.project_id
  network_name = "shared-gke-network"

  subnets = [
    for env, cfg in local.environments : {
      subnet_name           = "gke-subnet-${env}"
      subnet_ip             = cfg.node_cidr
      subnet_region         = var.region
      subnet_private_access = "true"
    }
  ]

  secondary_ranges = {
    for env, cfg in local.environments :
    "gke-subnet-${env}" => [
      {
        range_name    = "${env}-pods"
        ip_cidr_range = cidrsubnet(cfg.range_base, 1, 0)
      },
      {
        range_name    = "${env}-services"
        ip_cidr_range = cidrsubnet(cfg.range_base, 1, 1)
      },
    ]
  }
}

# Data source to reference existing network in non-gitops workspaces
data "google_compute_network" "shared_network" {
  count   = terraform.workspace != "gitops" ? 1 : 0
  project = var.project_id
  name    = "shared-gke-network"
}

# Single Cloud Router (shared across all clusters, only created in gitops)
resource "google_compute_router" "shared_router" {
  count   = terraform.workspace == "gitops" ? 1 : 0
  project = var.project_id
  name    = "shared-gke-router"
  network = module.shared-network[0].network_name
  region  = var.region
}

# Single Cloud NAT (shared across all clusters, only created in gitops)
resource "google_compute_router_nat" "shared_nat" {
  count                              = terraform.workspace == "gitops" ? 1 : 0
  project                            = var.project_id
  name                               = "shared-gke-nat"
  router                             = google_compute_router.shared_router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
