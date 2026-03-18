locals {
  cluster_types = toset(["gitops", "dev", "staging"])
  # Master CIDR offsets for different environments
  master_cidr_offsets = {
    dev     = "0"
    staging = "1"
    gitops  = "2"
  }
  # Shared network name - gitops creates, others reference via data source
  shared_network_name = terraform.workspace == "gitops" ? module.shared-network[0].network_name : data.google_compute_network.shared_network[0].name

  # Base app definitions
  # Each app has an optional `clusters` field to control which clusters it deploys to.
  # Omit `clusters` to deploy to all clusters (gitops, dev, staging).
  apps = {
    # --- Monitoring ---
    prometheus = {
      name           = "prometheus-monitoring"
      chart          = "kube-prometheus-stack"
      repoURL        = "https://prometheus-community.github.io/helm-charts"
      targetRevision = "82.10.3"
      namespace      = "monitoring"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-prometheus.yaml")))
    }
    loki = {
      name           = "loki"
      chart          = "loki"
      repoURL        = "https://grafana.github.io/helm-charts"
      targetRevision = "6.54.0"
      namespace      = "logging"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-loki.yaml")))
    }
    kiali = {
      name           = "kiali-server"
      chart          = "kiali-server"
      repoURL        = "https://kiali.org/helm-charts"
      targetRevision = "2.23.0"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-kiali.yaml")))
    }

    # --- Service Mesh (Istio) ---
    istio-base = {
      name           = "istio-base"
      chart          = "base"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.29.*"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-base.yaml")))
    }
    istiod = {
      name           = "istiod"
      chart          = "istiod"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.29.*"
      namespace      = "istio-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-istiod.yaml")))
    }
    istio-gateway = {
      name           = "istio-ingressgateway"
      chart          = "gateway"
      repoURL        = "https://istio-release.storage.googleapis.com/charts"
      targetRevision = "1.29.*"
      namespace      = "istio-gateways"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-gateway.yaml")))
    }

    # --- Certificate Management ---
    cert-manager = {
      name           = "cert-manager"
      chart          = "cert-manager"
      repoURL        = "https://charts.jetstack.io"
      targetRevision = "1.20.0"
      namespace      = "cert-manager"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-certmanager.yaml")))
    }

    # --- Autoscaling ---
    vpa = {
      name           = "vpa"
      chart          = "vpa"
      repoURL        = "https://charts.fairwinds.com/stable"
      targetRevision = "4.10.1"
      namespace      = "vpa"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-vpa.yaml")))
    }

    # --- Deployments ---
    argo-rollouts = {
      name           = "argo-rollouts"
      chart          = "argo-rollouts"
      repoURL        = "https://argoproj.github.io/argo-helm"
      targetRevision = "2.40.6"
      namespace      = "argo-rollouts"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-argo-rollouts.yaml")))
    }

    # --- External Secrets Operator ---
    external-secrets = {
      name           = "external-secrets"
      chart          = "external-secrets"
      repoURL        = "https://charts.external-secrets.io"
      targetRevision = "2.1.0"
      namespace      = "external-secrets"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-external-secrets.yaml")))
    }

    # --- External DNS ---
    external-dns = {
      name           = "external-dns"
      chart          = "external-dns"
      repoURL        = "https://kubernetes-sigs.github.io/external-dns"
      targetRevision = "1.20.0"
      namespace      = "external-dns"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-external-dns.yaml")))
    }

    # --- Metrics Server ---
    metrics-server = {
      name           = "metrics-server"
      chart          = "metrics-server"
      repoURL        = "https://kubernetes-sigs.github.io/metrics-server"
      targetRevision = "3.13.0"
      namespace      = "kube-system"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-metrics-server.yaml")))
    }

    # --- Reloader (auto-restart pods on ConfigMap/Secret changes) ---
    reloader = {
      name           = "reloader"
      chart          = "reloader"
      repoURL        = "https://stakater.github.io/stakater-charts"
      targetRevision = "2.2.9"
      namespace      = "reloader"
      values         = indent(8, yamlencode(file("${path.module}/templates/values-reloader.yaml")))
    }

    # --- Sample App ---
    bookinfo = {
      name           = "bookinfo"
      chart          = "bookinfo"
      repoURL        = "https://basic-techno.github.io/helm-charts/"
      targetRevision = "0.1.0"
      namespace      = "bookinfo"
      clusters       = ["dev"]
      values         = indent(8, yamlencode(file("${path.module}/templates/values-bookinfo.yaml")))
    }
  }

  # Cluster map for ArgoCD - all 3 clusters registered via Workload Identity
  argocd_clusters = terraform.workspace == "gitops" ? {
    gitops = {
      name     = "gitops-cluster"
      endpoint = data.google_container_cluster.gitops[0].endpoint
      ca_cert  = data.google_container_cluster.gitops[0].master_auth[0].cluster_ca_certificate
    }
    dev = {
      name     = "dev-cluster"
      endpoint = data.google_container_cluster.dev[0].endpoint
      ca_cert  = data.google_container_cluster.dev[0].master_auth[0].cluster_ca_certificate
    }
    staging = {
      name     = "staging-cluster"
      endpoint = data.google_container_cluster.staging[0].endpoint
      ca_cert  = data.google_container_cluster.staging[0].master_auth[0].cluster_ca_certificate
    }
  } : {}

  # Per-cluster apps: deploy each app only to clusters listed in its `clusters` field.
  # If `clusters` is omitted, the app deploys to all clusters.
  all_cluster_apps = terraform.workspace == "gitops" ? merge([
    for cluster_name, cluster in local.argocd_clusters : {
      for app_key, app in local.apps : "${cluster_name}-${app_key}" => merge(app, {
        project     = "project-${cluster_name}"
        dest_server = "https://${cluster.endpoint}"
      }) if contains(lookup(app, "clusters", ["gitops", "dev", "staging"]), cluster_name)
    }
  ]...) : {}

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
    apps     = local.all_cluster_apps
    clusters = local.argocd_clusters
  })
}
