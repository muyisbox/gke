locals {
  # Single source of truth for all environments.
  # To add a new environment (e.g. "prod"):
  #   1. Add an entry here with a unique node_cidr, range_base, and master_cidr_offset
  #   2. Create gke-applications/prod/ with app definitions
  #   3. Run: terraform workspace new prod && terraform apply
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

  # All non-gitops workspaces — used to discover remote clusters for ArgoCD
  remote_workspaces = [for env in keys(local.environments) : env if env != "gitops"]

  # Derived lookups (keep backwards-compatible names used elsewhere)
  master_cidr_offsets = { for env, cfg in local.environments : env => tostring(cfg.master_cidr_offset) }
  # Shared network name - gitops creates, others reference via data source
  shared_network_name = terraform.workspace == "gitops" ? module.shared-network[0].network_name : data.google_compute_network.shared_network[0].name

  # Cluster map for ArgoCD - gitops always present, remote clusters only when they exist
  argocd_clusters = terraform.workspace == "gitops" ? merge(
    {
      gitops = {
        name     = "gitops-cluster"
        endpoint = data.google_container_cluster.gitops[0].endpoint
        ca_cert  = data.google_container_cluster.gitops[0].master_auth[0].cluster_ca_certificate
      }
    },
    {
      for name, cluster in data.google_container_cluster.remote : name => {
        name     = "${name}-cluster"
        endpoint = cluster.endpoint
        ca_cert  = cluster.master_auth[0].cluster_ca_certificate
      }
    }
  ) : {}

  # Clusters whose secrets are managed by ESO (all except gitops)
  eso_managed_clusters = terraform.workspace == "gitops" ? {
    for k, v in local.argocd_clusters : k => v if k != "gitops"
  } : {}

  charts = {
    argocd = {
      namespace = var.argocd.namespace
      app       = var.argocd.app
      values    = [local.argocd-values]
    }
    argocd_apps = {
      namespace = var.argocd_apps.namespace
      app       = var.argocd_apps.app
      values    = [local.apps-values]
    }
  }
  argocd-values = file("${path.module}/templates/argocd-values.yaml")
  apps-values = templatefile("${path.module}/templates/apps-values.yaml", {
    clusters = local.argocd_clusters
  })
}
