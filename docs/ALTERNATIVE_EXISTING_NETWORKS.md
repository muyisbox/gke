# Alternative: Keep Existing Networks, Add Shared NAT

If you prefer to keep your existing per-workspace networks and just add a shared NAT Gateway to one of them, here's a simpler approach:

## Option A: Shared NAT in Primary Network

1. **Choose one network as primary** (e.g., dev network)
2. **Peer other networks to the primary**
3. **Route traffic through primary network's NAT**

### Step 1: Add NAT to Existing Dev Network

```hcl
# In network.tf - uncomment and modify the router/NAT section:

# Cloud Router for NAT Gateway (only in dev workspace)  
resource "google_compute_router" "router" {
  count   = terraform.workspace == "dev" ? 1 : 0
  project = var.project_id
  name    = "${var.network}-shared-router"
  network = module.gcp-network.network_name
  region  = var.region
}

# Shared Cloud NAT (only in dev workspace)
resource "google_compute_router_nat" "nat" {
  count                              = terraform.workspace == "dev" ? 1 : 0
  project                            = var.project_id
  name                               = "${var.network}-shared-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
```

### Step 2: Peer Networks (Optional)

If you want staging/gitops clusters to use the dev NAT:

```hcl
# Network peering resources (add to each non-dev workspace)
resource "google_compute_network_peering" "peering_to_dev" {
  count        = terraform.workspace != "dev" ? 1 : 0
  name         = "${terraform.workspace}-to-dev-peering"
  network      = module.gcp-network.network_self_link
  peer_network = "projects/${var.project_id}/global/networks/gke-network-dev"
}
```

## Option B: External NAT Gateway Project

Create a separate "shared-infrastructure" project with just the NAT Gateway:

### Benefits:
- **Cost**: Single NAT Gateway (~$45/month total vs $135/month for 3)
- **Simple**: No network changes required
- **Isolated**: Shared infrastructure in separate project

### Implementation:
1. Create shared infrastructure project
2. Set up VPC peering or Shared VPC
3. Route traffic through shared NAT

## Cost Comparison

| Approach | Monthly Cost | Complexity | Migration Risk |
|----------|-------------|------------|----------------|
| Current (3 NATs) | ~$135 | Low | None |
| Shared Network | ~$45 | High | High |
| Shared NAT in Dev | ~$45 | Medium | Low |
| External NAT Project | ~$45 | Medium | Medium |

## Recommendation

For **minimal risk** and **immediate cost savings**, use **Option A** (Shared NAT in Dev Network):

1. Deploy NAT only in dev workspace
2. Keep existing network architecture  
3. Optionally peer other networks to dev for shared NAT access
4. Save ~$90/month with minimal changes

This gives you the cost benefits without the complexity of network migration.