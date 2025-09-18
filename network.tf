# OLD PER-WORKSPACE NETWORK CONFIGURATION - REPLACED WITH SHARED NETWORK
# This configuration created separate networks per workspace which was expensive
# Now using shared-network.tf for cost optimization

# module "gcp-network" {
#   source  = "terraform-google-modules/network/google"
#   version = ">= 4.0.1"
# 
#   project_id   = var.project_id
#   network_name = "${var.network}-${terraform.workspace}"
# 
#   subnets = [
#     {
#       subnet_name   = "${var.subnetwork}-${terraform.workspace}"
#       subnet_ip     = lookup(local.subnet_cidrs, terraform.workspace)
#       subnet_region = var.region
#     },
#   ]
# 
#   secondary_ranges = {
#     ("${var.subnetwork}-${terraform.workspace}") = [
#       {
#         range_name    = var.ip_range_pods_name
#         ip_cidr_range = "***********/18"
#       },
#       {
#         range_name    = var.ip_range_services_name
#         ip_cidr_range = "************/18"
#       },
#     ]
#   }
# }
# 
# # Cloud Router for NAT Gateway
# resource "google_compute_router" "router" {
#   project = var.project_id
#   name    = "${var.network}-router-${terraform.workspace}"
#   network = module.gcp-network.network_name
#   region  = var.region
# }
# 
# # Cloud NAT for outbound internet access
# resource "google_compute_router_nat" "nat" {
#   project                            = var.project_id
#   name                               = "${var.network}-nat-${terraform.workspace}"
#   router                             = google_compute_router.router.name
#   region                             = var.region
#   nat_ip_allocate_option             = "AUTO_ONLY"
#   source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
# 
#   log_config {
#     enable = true
#     filter = "ERRORS_ONLY"
#   }
# }
