# Shared Network Infrastructure
# The shared network already exists - all workspaces reference it via data source
# This avoids workspace state conflicts for shared resources

# Data source to reference existing shared network
data "google_compute_network" "shared_network" {
  project = var.project_id
  name    = "shared-gke-network"
}

# Note: Router and NAT are managed by the network owner
# If these need to be recreated, do so outside of workspace-based Terraform

# Optional: Static NAT IP for consistent outbound IP
# resource "google_compute_address" "nat_ip" {
#   project = var.project_id
#   name    = "shared-nat-ip"
#   region  = var.region
# }