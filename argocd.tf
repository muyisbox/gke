
## This installs argo into the cluster
module "argocd" {
  source = "./modules/helm"

  namespace  = lookup(local.charts.argocd, "namespace", "default")
  repository = null
  app        = lookup(local.charts.argocd, "app")
  values     = lookup(local.charts.argocd, "values", [])
  depends_on = [
    module.gke
  ]
}


module "argocd-apps" {
  source = "./modules/helm"

  namespace  = lookup(local.charts.argocd_apps, "namespace", "default")
  repository = null
  app        = lookup(local.charts.argocd_apps, "app")
  values     = lookup(local.charts.argocd_apps, "values", [])
  depends_on = [
    module.argocd, module.gke
  ]
}

# resource "kubernetes_manifest" "kuma_mtls" {
#   manifest   = yamldecode(file("${path.module}/templates/kuma-mtls.yaml"))
#   depends_on = [module.argocd-apps]
# }

