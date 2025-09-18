module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  project_id                 = var.project_id
  name                       = "${terraform.workspace}-cluster"
  region                     = var.region
  zones                      = var.zones
  network                    = module.shared-network.network_name
  subnetwork                 = "gke-subnet-${terraform.workspace}"
  enable_private_nodes       = true
  enable_private_endpoint    = false
  master_ipv4_cidr_block     = "172.19.${local.master_cidr_offsets[terraform.workspace]}.0/28"
  deletion_protection        = false
  ip_range_pods              = "${terraform.workspace}-pods"
  ip_range_services          = "${terraform.workspace}-services"
  http_load_balancing        = false
  network_policy             = false
  horizontal_pod_autoscaling = true
  filestore_csi_driver       = false
  release_channel            = "UNSPECIFIED"
  kubernetes_version         = data.google_container_engine_versions.gke-version.latest_master_version

  node_pools = [
    {
      name               = "node-pool-01"
      machine_type       = "c2-standard-4"
      node_locations     = "us-central1-b,us-central1-c"
      min_count          = 1
      max_count          = 2
      local_ssd_count    = 0
      spot               = true
      disk_size_gb       = 20
      disk_type          = "pd-standard"
      image_type         = "COS_CONTAINERD"
      enable_gcfs        = false
      enable_gvnic       = false
      auto_repair        = true
      auto_upgrade       = false
      service_account    = var.compute_engine_service_account
      preemptible        = false
      initial_node_count = 1
      version            = data.google_container_engine_versions.gke-version.latest_node_version
    },
    {
      name               = "node-pool-02"
      machine_type       = "c2-standard-4"
      node_locations     = "us-central1-b,us-central1-c"
      min_count          = 1
      max_count          = 2
      local_ssd_count    = 0
      spot               = true
      disk_size_gb       = 20
      disk_type          = "pd-standard"
      image_type         = "COS_CONTAINERD"
      enable_gcfs        = false
      enable_gvnic       = false
      auto_repair        = true
      auto_upgrade       = false
      service_account    = var.compute_engine_service_account
      preemptible        = false
      initial_node_count = 1
      version            = data.google_container_engine_versions.gke-version.latest_node_version
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

  depends_on = [module.shared-network]
}