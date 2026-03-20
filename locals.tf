locals {
  # Stable alphabetical ordering used to derive per-environment indexes
  sorted_envs = sort(keys(var.environments))
  env_index   = { for env in local.sorted_envs : env => index(local.sorted_envs, env) }

  # All non-gitops workspaces — used to discover remote clusters for ArgoCD
  remote_workspaces = [for env in local.sorted_envs : env if env != "gitops"]

  # Derived lookups (keep backwards-compatible names used elsewhere)
  # range_base: cidrsubnet("172.16.0.0/12", 5, i) gives 172.16.0.0/17, 172.17.0.0/17, 172.18.0.0/17 ...
  master_cidr_offsets = { for env in local.sorted_envs : env => tostring(local.env_index[env]) }
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
