# State migration for shared network resources
# When we added count to the shared-network module, resource addresses changed
# These moved blocks tell Terraform to rename resources in state instead of destroying them

# Only apply these moves in gitops workspace where the module exists

# VPC Network
moved {
  from = module.shared-network.module.vpc.google_compute_network.network
  to   = module.shared-network[0].module.vpc.google_compute_network.network
}

# Subnets
moved {
  from = module.shared-network.module.subnets.google_compute_subnetwork.subnetwork
  to   = module.shared-network[0].module.subnets.google_compute_subnetwork.subnetwork
}

# Routes (if any)
moved {
  from = module.shared-network.module.routes
  to   = module.shared-network[0].module.routes
}

# Cloud Router
moved {
  from = google_compute_router.shared_router
  to   = google_compute_router.shared_router[0]
}

# Cloud NAT
moved {
  from = google_compute_router_nat.shared_nat
  to   = google_compute_router_nat.shared_nat[0]
}
