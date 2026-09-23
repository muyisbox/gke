# Shared network: one VPC, one router, one NAT for every cluster.
# Owned by the gitops workspace; spokes read it through a data source.
# (Per-workspace VPCs were the original design — they tripled NAT cost.)

module "shared-network" {
  count = local.is_gitops ? 1 : 0

  source  = "terraform-google-modules/network/google"
  version = "~> 18.3"

  project_id   = var.project_id
  network_name = var.network_name

  subnets = [
    for env, cfg in var.environments : {
      subnet_name           = "gke-subnet-${env}"
      subnet_ip             = cfg.node_cidr
      subnet_region         = var.region
      subnet_private_access = "true"
    }
  ]

  # range_base is split in half: lower for pods, upper for services.
  secondary_ranges = {
    for env, cfg in var.environments :
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

data "google_compute_network" "shared_network" {
  count   = local.is_gitops ? 0 : 1
  project = var.project_id
  name    = var.network_name
}

resource "google_compute_router" "shared_router" {
  count   = local.is_gitops ? 1 : 0
  project = var.project_id
  name    = "shared-gke-router"
  network = module.shared-network[0].network_name
  region  = var.region
}

resource "google_compute_router_nat" "shared_nat" {
  count                              = local.is_gitops ? 1 : 0
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
