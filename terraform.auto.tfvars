project_id          = "kthw2-310821"
cluster_name        = "cluster"
region              = "us-central1"
zones               = ["us-central1-c", "us-central1-b", "us-central1-a"]
cluster_name_suffix = "dev"

compute_engine_service_account = "terraform@kthw2-310821.iam.gserviceaccount.com"

network           = "gke-network"
subnetwork        = "gke-subnet"
ip_range_pods     = "192.168.0.0/18"
ip_range_services = "192.168.64.0/18"


argocd = {
  namespace = "argocd"
  app = {
    name             = "argo-cd"
    version          = "6.11.1"
    chart            = "argo-cd"
    force_update     = true
    wait             = false
    recreate_pods    = false
    deploy           = true
    create_namespace = true
  }
}

argocd_apps = {
  namespace = "argocd"
  app = {
    name             = "argo-apps"
    version          = "2.0.0"
    chart            = "argocd-apps"
    force_update     = true
    wait             = false
    recreate_pods    = false
    deploy           = true
    create_namespace = true
  }
}



