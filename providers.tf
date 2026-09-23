# All three Kubernetes-facing providers talk to the cluster this workspace owns,
# authenticating with the caller's GCP access token.

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    token                  = local.cluster_token
    cluster_ca_certificate = local.cluster_ca_certificate
  }
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  token                  = local.cluster_token
  cluster_ca_certificate = local.cluster_ca_certificate
}

provider "kubectl" {
  host                   = local.cluster_endpoint
  token                  = local.cluster_token
  cluster_ca_certificate = local.cluster_ca_certificate
  load_config_file       = false
}
