# Shared Network Infrastructure
# This creates a single VPC network with one NAT Gateway that all clusters can use

# Shared VPC Network (create once, use for all clusters)
module "shared-network" {
  source  = "terraform-google-modules/network/google"
  version = ">= 4.0.1"

  project_id   = var.project_id
  network_name = "shared-gke-network"

  subnets = [
    # Dev environment subnet
    {
      subnet_name           = "gke-subnet-dev"
      subnet_ip            = "10.10.0.0/17"
      subnet_region        = var.region
      subnet_private_access = "true"
    },
    # Staging environment subnet  
    {
      subnet_name           = "gke-subnet-staging"
      subnet_ip            = "10.20.0.0/17"
      subnet_region        = var.region
      subnet_private_access = "true"
    },
    # GitOps environment subnet
    {
      subnet_name           = "gke-subnet-gitops"
      subnet_ip            = "10.30.0.0/17"
      subnet_region        = var.region
      subnet_private_access = "true"
    }
  ]

  secondary_ranges = {
    "gke-subnet-dev" = [
      {
        range_name    = "dev-pods"
        ip_cidr_range = "172.16.0.0/18"
      },
      {
        range_name    = "dev-services"
        ip_cidr_range = "172.16.64.0/18"
      },
    ]
    "gke-subnet-staging" = [
      {
        range_name    = "staging-pods"
        ip_cidr_range = "172.17.0.0/18"
      },
      {
        range_name    = "staging-services"
        ip_cidr_range = "172.17.64.0/18"
      },
    ]
    "gke-subnet-gitops" = [
      {
        range_name    = "gitops-pods"
        ip_cidr_range = "172.18.0.0/18"
      },
      {
        range_name    = "gitops-services"
        ip_cidr_range = "172.18.64.0/18"
      },
    ]
  }
}

# Single Cloud Router (shared across all clusters)
resource "google_compute_router" "shared_router" {
  project = var.project_id
  name    = "shared-gke-router"
  network = module.shared-network.network_name
  region  = var.region
}

# Single Cloud NAT (shared across all clusters)
resource "google_compute_router_nat" "shared_nat" {
  project                            = var.project_id
  name                               = "shared-gke-nat"
  router                             = google_compute_router.shared_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  # Optional: Reserve static NAT IPs for better IP allowlisting
  # nat_ips = [google_compute_address.nat_ip.self_link]
}

# Optional: Static NAT IP for consistent outbound IP
# resource "google_compute_address" "nat_ip" {
#   project = var.project_id
#   name    = "shared-nat-ip"
#   region  = var.region
# }