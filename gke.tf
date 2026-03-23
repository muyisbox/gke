module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  project_id                 = var.project_id
  name                       = "${terraform.workspace}-cluster"
  region                     = var.region
  zones                      = var.zones
  network                    = local.shared_network_name
  subnetwork                 = "gke-subnet-${terraform.workspace}"
  enable_private_nodes       = true
  enable_private_endpoint    = false
  master_ipv4_cidr_block     = "172.19.${local.master_cidr_offsets[terraform.workspace]}.0/28"
  deletion_protection        = false
  ip_range_pods              = "${terraform.workspace}-pods"
  ip_range_services          = "${terraform.workspace}-services"
  http_load_balancing        = false
  network_policy             = true
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false
  release_channel            = "REGULAR"
  cluster_autoscaling = {
    enabled                      = true
    enable_default_compute_class = true
    autoscaling_profile          = "OPTIMIZE_UTILIZATION"
    min_cpu_cores                = 0
    max_cpu_cores                = 48
    min_memory_gb                = 0
    max_memory_gb                = 192
    gpu_resources                = []
    auto_repair                  = true
    auto_upgrade                 = true
    disk_size                    = 30
    disk_type                    = "pd-standard"
  }

  node_pools = []

  node_pools_oauth_scopes = {
    all = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/compute",
    ]
  }

  node_pools_labels = {
    all = {}
  }

  node_pools_metadata = {
    all = {}
  }

  node_pools_taints = {
    all = []
  }

  node_pools_tags = {
    all = []
  }
}

# Grant the Terraform service account container.admin scoped to this cluster
resource "google_project_iam_member" "terraform_cluster_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:terraform@cluster-dreams.iam.gserviceaccount.com"

  condition {
    title       = "${terraform.workspace}-cluster-admin"
    description = "Scoped to ${terraform.workspace}-cluster only"
    expression  = "resource.name == \"projects/${var.project_id}/locations/${var.region}/clusters/${terraform.workspace}-cluster\" || resource.name.startsWith(\"projects/${var.project_id}/locations/${var.region}/clusters/${terraform.workspace}-cluster/\")"
  }
}