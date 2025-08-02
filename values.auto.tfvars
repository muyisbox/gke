# Cluster Configuration
# Defines basic properties of the GKE cluster including names and location.
cluster_name        = "cluster"                                           # Base name of the cluster
region              = "us-central1"                                       # The GCP region where the cluster is deployed
zones               = ["us-central1-c", "us-central1-b", "us-central1-a"] # Zones within the region for cluster deployment
cluster_name_suffix = "dev"                                               # Suffix to append to the cluster name indicating the environment

# Network Configuration
# Specifies the network settings for the cluster.
network           = "gke-network"     # Name of the GCP network to use for the cluster
subnetwork        = "gke-subnet"      # Name of the GCP subnetwork to use
ip_range_pods     = "192.168.0.0/18"  # CIDR block for pod IP allocation
ip_range_services = "192.168.64.0/18" # CIDR block for service IP allocation

# ArgoCD Configuration
# Sets up ArgoCD in the cluster to manage deployments and configurations.
argocd = {
  namespace = "argocd" # Kubernetes namespace where ArgoCD is deployed
  app = {
    name             = "argo-cd" # Name of the ArgoCD application
    version          = "8.2.3"  # Version of ArgoCD to deploy
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
    version          = "2.0.0"       # Version of the app to deploy
    chart            = "argocd-apps" # Helm chart for the app
    force_update     = true          # Force update the app if set to true
    wait             = false         # Wait for full deployment if true
    recreate_pods    = false         # Recreate pods on update if true
    deploy           = true          # Deploy the application if true
    create_namespace = true          # Create the namespace if it doesn't exist
  }
}
