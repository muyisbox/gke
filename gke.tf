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
    enabled             = true
    autoscaling_profile = "OPTIMIZE_UTILIZATION"
    min_cpu_cores       = 0
    max_cpu_cores       = 48
    min_memory_gb       = 0
    max_memory_gb       = 192
    gpu_resources       = []
    auto_repair         = true
    auto_upgrade        = true
    disk_size           = 30
    disk_type           = "pd-standard"
  }

  node_pools = [
    {
      name               = "node-pool-01"
      machine_type       = "e2-standard-4"
      node_locations     = "us-central1-b,us-central1-c"
      min_count          = 1
      max_count          = 4
      local_ssd_count    = 0
      spot               = false
      disk_size_gb       = 30
      disk_type          = "pd-ssd"
      image_type         = "COS_CONTAINERD"
      enable_gcfs        = false
      enable_gvnic       = false
      auto_repair        = true
      auto_upgrade       = true
      service_account    = ""
      preemptible        = false
      initial_node_count = 1
    },
  ]

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

    default-node-pool = {
      default-node-pool = true
    }
  }

  node_pools_metadata = {
    all = {}

    default-node-pool = {
      node-pool-metadata-custom-value = "my-node-pool"
    }
  }

  node_pools_taints = {
    all = []

    default-node-pool = [
      {
        key    = "default-node-pool"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }

  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
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