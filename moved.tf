# State moves. Keep these until every workspace has run an apply past the
# change that introduced them; removing one early makes Terraform destroy and
# recreate the resource instead of renaming it in state.

# 2026-03 — the shared network module gained `count` when the per-workspace
# VPCs were collapsed into one, which shifted every address under it.
moved {
  from = module.shared-network.module.vpc.google_compute_network.network
  to   = module.shared-network[0].module.vpc.google_compute_network.network
}

moved {
  from = module.shared-network.module.subnets.google_compute_subnetwork.subnetwork
  to   = module.shared-network[0].module.subnets.google_compute_subnetwork.subnetwork
}

moved {
  from = module.shared-network.module.routes
  to   = module.shared-network[0].module.routes
}

moved {
  from = google_compute_router.shared_router
  to   = google_compute_router.shared_router[0]
}

moved {
  from = google_compute_router_nat.shared_nat
  to   = google_compute_router_nat.shared_nat[0]
}

# 2026-09 — kubernetes provider v3 deprecates the unsuffixed resource names in
# favour of their _v1 equivalents.
moved {
  from = kubernetes_secret.argocd_cluster
  to   = kubernetes_secret_v1.argocd_cluster
}

# 2026-09 — the two ArgoCD Workload Identity bindings collapsed into one
# for_each keyed by Kubernetes service account name.
moved {
  from = google_service_account_iam_member.argocd_controller_wi[0]
  to   = google_service_account_iam_member.argocd_workload_identity["argocd-application-controller"]
}

moved {
  from = google_service_account_iam_member.argocd_server_wi[0]
  to   = google_service_account_iam_member.argocd_workload_identity["argocd-server"]
}

# 2026-09 — the ESO CRD data sources and manifests became a single for_each.
moved {
  from = kubectl_manifest.eso_crd_clustersecretstores[0]
  to   = kubectl_manifest.eso_crd["clustersecretstores"]
}

moved {
  from = kubectl_manifest.eso_crd_externalsecrets[0]
  to   = kubectl_manifest.eso_crd["externalsecrets"]
}

# 2026-09 — eso_wi renamed for consistency with the other identity bindings.
moved {
  from = google_service_account_iam_member.eso_wi
  to   = google_service_account_iam_member.eso_workload_identity
}

# 2026-09 — ESO CRD and ClusterSecretStore ownership moved to ArgoCD.
#
# destroy = false is not optional here. Deleting a CRD cascades to every custom
# resource of that kind, so a plain removal would take the ExternalSecrets and
# ClusterSecretStores with it. These blocks drop the state entries and leave the
# live objects for ArgoCD to keep managing.
removed {
  from = kubectl_manifest.eso_crd

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubectl_manifest.eso_cluster_secret_store

  lifecycle {
    destroy = false
  }
}
