locals {
  cluster_types = toset(["gitops", "dev", "staging"])
  # Master CIDR offsets for different environments
  master_cidr_offsets = {
    dev     = "0"
    staging = "1"
    gitops  = "2"
  }
  # Shared network name - all workspaces reference existing network
  shared_network_name = data.google_compute_network.shared_network.name
  apps = {
    # --- Monitoring ---
    prometheus = {
      name           = "prometheus-monitoring"
      chart          = "kube-prometheus-stack"
      repoURL        = "https://prometheus-community.github.io/helm-charts"
      targetRevision = "82.10.3"
      project        = "boeing"
      namespace      = "monitoring"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-prometheus.yaml")))
    }
    loki = {
      name           = "loki"
      chart          = "loki"
      repoURL        = "https://grafana.github.io/helm-charts"
      targetRevision = "6.54.0"
      project        = "boeing"
      namespace      = "logging"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-loki.yaml")))
    }
    kiali = {
      name           = "kiali-server"
      chart          = "kiali-server"
      repoURL        = "https://kiali.org/helm-charts"
      targetRevision = "2.23.0"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-kiali.yaml")))
    }

    # --- Service Mesh (Istio) ---
    istio-base = {
      name           = "istio-base"
      chart          = "base"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.29.*"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-base.yaml")))
    }
    istiod = {
      name           = "istiod"
      chart          = "istiod"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.29.*"
      project        = "boeing"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-istiod.yaml")))
    }
    istio-gateway = {
      name           = "istio-ingressgateway"
      chart          = "gateway"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.29.*"
      project        = "boeing"
      namespace      = "istio-gateways"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-gateway.yaml")))
    }

    # --- Certificate Management ---
    cert-manager = {
      name           = "cert-manager"
      chart          = "cert-manager"
      repoURL        = "https://charts.jetstack.io"
      targetRevision = "1.20.0"
      project        = "boeing"
      namespace      = "cert-manager"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-certmanager.yaml")))
    }

    # --- Autoscaling ---
    vpa = {
      name           = "vpa"
      chart          = "vpa"
      repoURL        = "https://charts.fairwinds.com/stable"
      targetRevision = "4.10.1"
      project        = "boeing"
      namespace      = "vpa"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-vpa.yaml")))
    }

    # --- Deployments ---
    argo-rollouts = {
      name           = "argo-rollouts"
      chart          = "argo-rollouts"
      repoURL        = "https://argoproj.github.io/argo-helm"
      targetRevision = "2.40.6"
      project        = "boeing"
      namespace      = "argo-rollouts"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-argo-rollouts.yaml")))
    }

    # --- External Secrets Operator ---
    external-secrets = {
      name           = "external-secrets"
      chart          = "external-secrets"
      repoURL        = "https://charts.external-secrets.io"
      targetRevision = "2.1.0"
      project        = "boeing"
      namespace      = "external-secrets"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-external-secrets.yaml")))
    }

    # --- External DNS ---
    external-dns = {
      name           = "external-dns"
      chart          = "external-dns"
      repoURL        = "https://kubernetes-sigs.github.io/external-dns"
      targetRevision = "1.20.0"
      project        = "boeing"
      namespace      = "external-dns"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-external-dns.yaml")))
    }

    # --- Metrics Server ---
    metrics-server = {
      name           = "metrics-server"
      chart          = "metrics-server"
      repoURL        = "https://kubernetes-sigs.github.io/metrics-server"
      targetRevision = "3.13.0"
      project        = "boeing"
      namespace      = "kube-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-metrics-server.yaml")))
    }

    # --- Reloader (auto-restart pods on ConfigMap/Secret changes) ---
    reloader = {
      name           = "reloader"
      chart          = "reloader"
      repoURL        = "https://stakater.github.io/stakater-charts"
      targetRevision = "2.2.9"
      project        = "boeing"
      namespace      = "reloader"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-reloader.yaml")))
    }

    # --- Sample App ---
    bookinfo = {
      name           = "bookinfo"
      chart          = "bookinfo"
      repoURL        = "https://basic-techno.github.io/helm-charts/"
      targetRevision = "0.1.0"
      project        = "boeing"
      namespace      = "bookinfo"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-bookinfo.yaml")))
    }
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
        sourceRepos = [
          "https://prometheus-community.github.io/helm-charts",
          "https://istio-release.storage.googleapis.com/charts",
          "https://charts.fairwinds.com/stable",
          "https://basic-techno.github.io/helm-charts/",
          "https://charts.jetstack.io",
          "https://grafana.github.io/helm-charts",
          "https://kiali.org/helm-charts",
          "https://argoproj.github.io/argo-helm",
          "https://charts.external-secrets.io",
          "https://kubernetes-sigs.github.io/external-dns",
          "https://kubernetes-sigs.github.io/metrics-server",
          "https://stakater.github.io/stakater-charts",
        ]
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

