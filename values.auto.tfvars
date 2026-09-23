# Project
project_id                = "cluster-dreams"
terraform_service_account = "terraform@cluster-dreams.iam.gserviceaccount.com"

# Location
region = "us-central1"
zones  = ["us-central1-c", "us-central1-b", "us-central1-a"]

# Environments
# Each key is a Terraform workspace and produces one cluster.
# To add one (e.g. "prod"):
#   1. Add an entry below with a free node_cidr, range_base and master_cidr_offset
#   2. Create gke-applications/prod/ with its app definitions
#   3. Add the workspace to _WORKSPACES in cicd/cloudbuild.yaml
#   4. terraform workspace new prod && terraform apply
environments = {
  dev = {
    node_cidr          = "10.10.0.0/17"
    range_base         = "172.16.0.0/17"
    master_cidr_offset = 0
  }
  staging = {
    node_cidr          = "10.20.0.0/17"
    range_base         = "172.17.0.0/17"
    master_cidr_offset = 1
  }
  gitops = {
    node_cidr          = "10.30.0.0/17"
    range_base         = "172.18.0.0/17"
    master_cidr_offset = 2
  }
}

# Cluster shape
# Capacity comes from node auto-provisioning; there are no static node pools.
# Every attribute is optional and falls back to the default in variables.tf.
cluster_autoscaling = {
  enabled                      = true
  enable_default_compute_class = true
  autoscaling_profile          = "OPTIMIZE_UTILIZATION"
  min_cpu_cores                = 0
  max_cpu_cores                = 48
  min_memory_gb                = 0
  max_memory_gb                = 192
  disk_size                    = 30
  disk_type                    = "pd-standard"
  auto_repair                  = true
  auto_upgrade                 = true
  gpu_resources                = []
}

# ArgoCD control plane (gitops workspace only)
argocd = {
  namespace = "argocd"
  app = {
    name    = "argo-cd"
    chart   = "argo-cd"
    version = "10.9.2" # Argo CD v3.5.3
    wait    = false
  }
}

# Renders the per-cluster AppProjects and ApplicationSets
argocd_apps = {
  namespace = "argocd"
  app = {
    name    = "argocd-apps"
    chart   = "argocd-apps"
    version = "2.0.5"
    wait    = false
  }
}
