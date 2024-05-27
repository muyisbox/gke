module "gcp-network" {
  source  = "terraform-google-modules/network/google"
  version = ">= 4.0.1"

  project_id   = var.project_id
  network_name = "${var.network}-${terraform.workspace}"

  subnets = [
    {
      subnet_name   = "${var.subnetwork}-${terraform.workspace}"
      subnet_ip     = lookup(local.subnet_cidrs, terraform.workspace)
      subnet_region = var.region
    },
  ]

  secondary_ranges = {
    ("${var.subnetwork}-${terraform.workspace}") = [
      {
        range_name    = var.ip_range_pods_name
        ip_cidr_range = "192.168.0.0/18"
      },
      {
        range_name    = var.ip_range_services_name
        ip_cidr_range = "192.168.64.0/18"
      },
    ]
  }
}