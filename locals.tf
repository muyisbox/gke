locals {
  # All non-gitops workspaces — used to discover remote clusters for ArgoCD
  remote_workspaces = [for env in keys(var.environments) : env if env != "gitops"]

  # Derived lookups
  master_cidr_offsets = { for env, cfg in var.environments : env => tostring(cfg.master_cidr_offset) }
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
