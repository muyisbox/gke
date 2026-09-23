output "cluster_name" {
  description = "Name of the GKE cluster this workspace owns."
  value       = module.gke.name
}

output "kubernetes_endpoint" {
  description = "Control-plane endpoint of this workspace's cluster."
  sensitive   = true
  value       = module.gke.endpoint
}

output "ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  sensitive   = true
  value       = module.gke.ca_certificate
}

output "service_account" {
  description = "Default service account the cluster's nodes run as."
  value       = module.gke.service_account
}

output "network_name" {
  description = "Shared VPC backing every cluster."
  value       = local.shared_network_name
}

output "subnet_name" {
  description = "Subnet this workspace's nodes live in."
  value       = local.subnet_name
}

output "subnet_secondary_ranges" {
  description = "Secondary pod/service ranges on the shared subnets. Only populated in the gitops workspace, which owns them."
  value       = local.is_gitops ? module.shared-network[0].subnets_secondary_ranges : []
}

output "registered_argocd_clusters" {
  description = "Clusters ArgoCD is currently registered against. Empty outside the gitops workspace."
  value       = keys(local.argocd_clusters)
}

output "cluster_connect" {
  description = "Command to write a kubeconfig entry for this cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.name} --region ${var.region} --project ${var.project_id}"
}
