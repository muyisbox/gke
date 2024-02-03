locals {
  cluster_type = "gitops"

  apps = {
    prometheus = {
      name           = "prometheus-monitoring"
      chart          = "kube-prometheus-stack"
      repoURL        = "https://prometheus-community.github.io/helm-charts"
      targetRevision = "55.1.0"
      project        = "boeing"
      namespace      = "monitoring"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-prometheus.yaml")))
    }
    istio-base = {
      name           = "istio-base-1-18-2"
      chart          = "base"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.18.2"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-base.yaml")))
    }
    istiod = {
      name           = "istiod-1-18-2"
      chart          = "istiod"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.18.2"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-istiod.yaml")))
    }
    istiod-canary = {
      name           = "istiod"
      chart          = "istiod"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.19.4"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-istiod-new.yaml")))
    }
    istio-gateway = {
      name           = "istio-ingressgateway"
      chart          = "gateway"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.19.4"
      project        = "boeing"
      namespace      = "istio-gateways"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-gateway.yaml")))
    }
    bookinfo = {
      name           = "bookinfo"
      chart          = "bookinfo"
      repoURL        = "https://basic-techno.github.io/helm-charts/"
      targetRevision = "0.1.0"
      project        = "boeing"
      namespace      = "bookinfo"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-bookinfo.yaml")))
    }
    cert-manager = {
      name           = "cert-manager"
      chart          = "cert-manager"
      repoURL        = "https://charts.jetstack.io"
      targetRevision = "1.12.3"
      project        = "boeing"
      namespace      = "cert-manager"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-certmanager.yaml")))
    }
    kpack = {
      name           = "kpack-chart"
      chart          = "kpack-chart"
      repoURL        = "oci://registry-1.docker.io/muyisbox"
      targetRevision = "0.11.2"
      project        = "boeing"
      namespace      = "kpack"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-kpack.yaml")))
    }
    loki = {
      name           = "loki-stack"
      chart          = "loki-stack"
      repoURL        = "https://grafana.github.io/helm-charts"
      targetRevision = "2.9.11"
      project        = "boeing"
      namespace      = "logging"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-loki.yaml")))
    }
    kiali = {
      name           = "kiali-server"
      chart          = "kiali-server"
      repoURL        = "https://kiali.org/helm-charts"
      targetRevision = "1.77.0"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-kiali.yaml")))
    }
    argo-rollouts = {
      name           = "argo-rollouts"
      chart          = "argo-rollouts"
      repoURL        = "https://argoproj.github.io/argo-helm"
      targetRevision = "2.32.*"
      project        = "boeing"
      namespace      = "argo-rollouts"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-argo-rollouts.yaml")))
    }
    kuma = {
      name           = "kuma"
      chart          = "kuma"
      repoURL        = "https://kumahq.github.io/charts"
      targetRevision = "2.5.*"
      project        = "boeing"
      namespace      = "kong-mesh-system"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-kuma.yaml")))
    }
    argo-rollouts = {
      name           = "argo-rollouts"
      chart          = "argo-rollouts"
      repoURL        = "https://argoproj.github.io/argo-helm"
      targetRevision = "2.32.*"
      project        = "boeing"
      namespace      = "argo-rollouts"
      values         = indent(10, yamlencode(file("${path.module}/templates/values-argo-rollouts.yaml")))
    }
  }
}


locals {
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
    apps = local.apps
  })

}
