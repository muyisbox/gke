# Project Configuration
project_id                     = "cluster-dreams"                         # Replace with your actual GCP project ID
compute_engine_service_account = "create"                                 # Creates a new service account for the nodes

# Cluster Configuration
# Defines basic properties of the GKE cluster including names and location.
cluster_name        = "cluster"                                           # Base name of the cluster
region              = "us-central1"                                       # The GCP region where the cluster is deployed
zones               = ["us-central1-c", "us-central1-b", "us-central1-a"] # Zones within the region for cluster deployment
cluster_name_suffix = "dev"                                               # Suffix to append to the cluster name indicating the environment


# Environments
# To add a new environment (e.g. "prod"):
#   1. Add an entry below with a unique node_cidr, range_base, and master_cidr_offset
#   2. Create gke-applications/prod/ with app definitions
#   3. Run: terraform workspace new prod && terraform apply
environments = {
  dev     = { node_cidr = "10.10.0.0/17" }
  gitops  = { node_cidr = "10.30.0.0/17" }
  staging = { node_cidr = "10.20.0.0/17" }
}

# ArgoCD Configuration
# Sets up ArgoCD in the cluster to manage deployments and configurations.
argocd = {
  namespace = "argocd" # Kubernetes namespace where ArgoCD is deployed
  app = {
    name             = "argo-cd" # Name of the ArgoCD application
    version          = "9.4.10"  # ArgoCD v3.3.3
    chart            = "argo-cd" # Helm chart name for ArgoCD
    force_update     = true      # Force update the app if true
    wait             = false     # If true, the Terraform provider waits for the app to be fully deployed
    recreate_pods    = false     # Force recreate pods during helm upgrade if true
    deploy           = true      # Deploy the application if true
    create_namespace = true      # Create the Kubernetes namespace if it doesn't exist
  }
}

# ArgoCD Applications Configuration#
# Defines the setup for applications managed by ArgoCD.
argocd_apps = {
  namespace = "argocd" # Kubernetes namespace for ArgoCD applications
  app = {
    name             = "argocd-apps" # Name of the app deployment managed by ArgoCD
    version          = "2.0.4"       # Version of the app to deploy
    chart            = "argocd-apps" # Helm chart for the app
    force_update     = true          # Force update the app if set to true
    wait             = false         # Wait for full deployment if true
    recreate_pods    = false         # Recreate pods on update if true
    deploy           = true          # Deploy the application if true
    create_namespace = true          # Create the namespace if it doesn't exist
  }
}
