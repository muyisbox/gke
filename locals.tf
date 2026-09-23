locals {
  # --- Workspace role -------------------------------------------------------
  # The gitops workspace is the hub: it owns the shared VPC/router/NAT, runs
  # ArgoCD, and registers every other cluster. Spokes only build their own
  # cluster and read the shared network.
  is_gitops = terraform.workspace == var.gitops_workspace
  env       = terraform.workspace
  spokes    = [for env in keys(var.environments) : env if env != var.gitops_workspace]

  cluster_name        = "${local.env}-cluster"
  gitops_cluster_name = "${var.gitops_workspace}-cluster"

  # --- Networking -----------------------------------------------------------
  # Equivalent to the original "172.19.<offset>.0/28" literal: newbits 12 yields
  # a /28, and offset*16 lands each block on a whole third octet.
  master_ipv4_cidr_block = cidrsubnet(
    var.master_cidr_supernet, 12, var.environments[local.env].master_cidr_offset * 16
  )

  shared_network_name = local.is_gitops ? module.shared-network[0].network_name : data.google_compute_network.shared_network[0].name
  subnet_name         = "gke-subnet-${local.env}"

  # --- Cluster connection (consumed by the helm/kubernetes/kubectl providers) ---
  cluster_endpoint       = "https://${module.gke.endpoint}"
  cluster_token          = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)

  # --- ArgoCD cluster registry ---------------------------------------------
  # Remote clusters come and go with the nightly destroy/recreate cycle, so the
  # set is discovered from the live API rather than assumed from var.environments.
  existing_cluster_names = local.is_gitops ? toset([
    for cluster in try(jsondecode(data.http.gke_clusters[0].response_body).clusters, []) : cluster.name
  ]) : toset([])

  reachable_spokes = toset([
    for env in local.spokes : env if contains(local.existing_cluster_names, "${env}-cluster")
  ])

  argocd_clusters = local.is_gitops ? merge(
    {
      (var.gitops_workspace) = {
        name     = local.gitops_cluster_name
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

  # The hub registers itself with a plain Secret (it is in-cluster); spokes are
  # brokered through Secret Manager + ESO so their credentials are never in state.
  eso_managed_clusters = {
    for k, v in local.argocd_clusters : k => v if k != var.gitops_workspace
  }

  # --- Chart values ---------------------------------------------------------
  argocd_values = templatefile("${path.module}/templates/argocd-values.yaml", {
    repo_url = var.apps_repo_url
    # Splat rather than [0]: this local is evaluated in spoke workspaces too,
    # where the service account does not exist.
    gcp_service_account = local.is_gitops ? one(google_service_account.argocd[*].email) : ""
  })

  apps_values = templatefile("${path.module}/templates/apps-values.yaml", {
    clusters      = local.argocd_clusters
    repo_url      = var.apps_repo_url
    repo_revision = var.apps_repo_revision
  })

  charts = {
    argocd = {
      namespace = var.argocd.namespace
      app       = var.argocd.app
      values    = [local.argocd_values]
    }
    argocd_apps = {
      namespace = var.argocd_apps.namespace
      app       = var.argocd_apps.app
      values    = [local.apps_values]
    }
  }
}
