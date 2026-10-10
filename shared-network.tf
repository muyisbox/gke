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

# Destroy-ordering barrier between the cluster and the subnets it sits in.
#
# module.gke already depends on this module through `network`, so Terraform
# destroys the cluster first. The problem is that the GKE DELETE operation
# reports DONE before Compute Engine has finished reclaiming the node
# instances, and the subnet delete then fails:
#
#   Error 400: The subnetwork resource '...gke-subnet-gitops' is already being
#   used by '...instances/gke-gitops-cluster-nap-...', resourceInUseByAnotherResource
#
# Dependencies are: shared-network <- this <- module.gke. Destroy runs in
# reverse, so the cluster goes first, this sleeps, then the subnets are
# removed. Create is not delayed.
resource "time_sleep" "node_drain" {
  count = local.is_gitops ? 1 : 0

  depends_on = [module.shared-network]

  create_duration  = "0s"
  destroy_duration = var.node_drain_wait
}

# Fixed address for the hub's observability ingress.
#
# Spokes ship telemetry to the hub across the shared VPC, so they need an
# endpoint that survives a cluster rebuild. An internal LoadBalancer picks a
# fresh IP each time it is recreated, which would mean editing every spoke's
# collector config after each teardown. Reserving the address pins it, and the
# Tempo Service claims it by loadBalancerIP.
#
# Taken from the top of the gitops node CIDR, well clear of the node addresses
# GKE allocates from the bottom.
resource "google_compute_address" "observability_hub" {
  count = local.is_gitops ? 1 : 0

  name         = "observability-hub-otlp-ilb"
  project      = var.project_id
  region       = var.region
  subnetwork   = local.subnet_name
  address_type = "INTERNAL"
  address      = var.observability_hub_ip

  depends_on = [module.shared-network]
}

# Second fixed address, for Prometheus remote-write. Metrics take their own
# path rather than the OTLP gateway so kube-prometheus-stack keeps doing its
# own scraping and ServiceMonitor discovery; only the write is redirected.
resource "google_compute_address" "metrics_hub" {
  count = local.is_gitops ? 1 : 0

  name         = "observability-hub-metrics-ilb"
  project      = var.project_id
  region       = var.region
  subnetwork   = local.subnet_name
  address_type = "INTERNAL"
  address      = var.metrics_hub_ip

  depends_on = [module.shared-network]
}
