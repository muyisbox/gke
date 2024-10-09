locals {
  cluster_types = toset(["gitops", "dev", "staging"])
  subnet_cidrs = {
    gitops  = "10.128.0.0/17"
    dev     = "10.160.0.0/17"
    staging = "10.192.0.0/17"
  }
  apps = {
    prometheus = {
      name           = "prometheus-monitoring"
      chart          = "kube-prometheus-stack"
      repoURL        = "https://prometheus-community.github.io/helm-charts"
      targetRevision = "57.2.0"
      project        = "boeing"
      namespace      = "monitoring"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-prometheus.yaml")))
    }
    istio-base = {
      name           = "istio-base-1-21"
      chart          = "base"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.21.*"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-base.yaml")))
    }
    istiod = {
      name           = "istiod-1-21"
      chart          = "istiod"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.21.*"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-istiod.yaml")))
    }
    vpa = {
      name           = "vpa"
      chart          = "vpa"
      repoURL        = "https://charts.fairwinds.com/stable"
      targetRevision = "4.4.6"
      project        = "boeing"
      namespace      = "vpa"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-vpa.yaml")))
    }
    istio-gateway = {
      name           = "istio-ingressgateway"
      chart          = "gateway"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.21.*"
      project        = "boeing"
      namespace      = "istio-gateways"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-gateway.yaml")))
    }
    bookinfo = {
      name           = "bookinfo"
      chart          = "bookinfo"
      repoURL        = "https://basic-techno.github.io/helm-charts/"
      targetRevision = "0.1.0"
      project        = "boeing"
      namespace      = "bookinfo"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-bookinfo.yaml")))
    }
    cert-manager = {
      name           = "cert-manager"
      chart          = "cert-manager"
      repoURL        = "https://charts.jetstack.io"
      targetRevision = "1.14.4"
      project        = "boeing"
      namespace      = "cert-manager"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-certmanager.yaml")))
    }
    # kpack = {
    #   name           = "kpack-chart"
    #   chart          = "kpack-chart"
    #   repoURL        = "oci://registry-1.docker.io/muyisbox"
    #   targetRevision = "0.11.2"
    #   project        = "boeing"
    #   namespace      = "kpack"
    #   values         = indent(8, yamlencode(file("${path.module}/templates/values-kpack.yaml")))
    # }
    loki = {
      name           = "loki-stack"
      chart          = "loki-stack"
      repoURL        = "https://grafana.github.io/helm-charts"
      targetRevision = "2.10.2"
      project        = "boeing"
      namespace      = "logging"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-loki.yaml")))
    }
    kiali = {
      name           = "kiali-server"
      chart          = "kiali-server"
      repoURL        = "https://kiali.org/helm-charts"
      targetRevision = "1.77.0"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-kiali.yaml")))
    }
    argo-rollouts = {
      name           = "argo-rollouts"
      chart          = "argo-rollouts"
      repoURL        = "https://argoproj.github.io/argo-helm"
      targetRevision = "2.35.*"
      project        = "boeing"
      namespace      = "argo-rollouts"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-argo-rollouts.yaml")))
    }
    # kuma = {
    #   name           = "kuma"
    #   chart          = "kuma"
    #   repoURL        = "https://kumahq.github.io/charts"
    #   targetRevision = "2.5.*"
    #   project        = "boeing"
    #   namespace      = "kong-mesh-system"
    #   values         = indent(8, yamlencode(file("${path.module}/templates/values-kuma.yaml")))
    # }
  }
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


locals {
  # Assuming var.apps is a map of objects where each object has properties like
  # project, repoURL, targetRevision, chart, name, values, and namespace
  argo_applications = yamlencode({
    applications = { for k, app in local.apps : k => {
      namespace  = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
      project    = app.project
      source = {
        repoURL        = app.repoURL
        targetRevision = app.targetRevision
        chart          = app.chart
        helm = {
          releaseName = app.name
          values      = app.values
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = app.namespace
      }
      syncPolicy = {
        managedNamespaceMetadata = {
          labels = {
            "istio.io/rev" = "stable"
          }
        }
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true", "ServerSideApply=true"]
      }
      }
    }
  })
  app_project = yamlencode({
    projects = {
      boeing = {
        namespace   = "argocd"
        finalizers  = ["resources-finalizer.argocd.argoproj.io"]
        description = "A Sample Project to Deploy applications into Boing Clusters"
        sourceRepos = ["*"]
        destinations = [
          {
            name      = "*"
            namespace = "*"
            server    = "https://kubernetes.default.svc"
          }
        ]
        namespaceResourceWhitelist = [
          {
            group = "*"
            kind  = "*"
          }
        ]
        clusterResourceWhitelist = [
          {
            group = "*"
            kind  = "*"
          }
        ]
      },
    }
  })
}

