
## This installs argo into the cluster
module "argocd" {
  source   = "./modules/helm"
  for_each = contains(["gitops", "dev", "staging"], terraform.workspace) ? toset([terraform.workspace]) : toset([])

  namespace  = lookup(local.charts.argocd, "namespace", "default")
  repository = "https://argoproj.github.io/argo-helm"
  app        = lookup(local.charts.argocd, "app", null)
  values     = lookup(local.charts.argocd, "values", [])

  depends_on = [
    module.gke
  ]

}


module "argocd-apps" {
  source     = "./modules/helm"
  for_each   = contains(["gitops", "dev", "staging"], terraform.workspace) ? toset([terraform.workspace]) : toset([])
  namespace  = lookup(local.charts.argocd_apps, "namespace", "default")
  repository = "https://argoproj.github.io/argo-helm"
  app        = lookup(local.charts.argocd_apps, "app")
  values     = lookup(local.charts.argocd_apps, "values", [])
  depends_on = [
    module.argocd, module.gke
  ]
}

