variable "project_id" {
  description = "The project ID to host the cluster in"
}

variable "cluster_name" {
  description = "The name for the GKE cluster"
}

variable "ip_range_pods" {
  description = "The secondary ip range to use for pods"
}

variable "ip_range_services" {
  description = "The secondary ip range to use for services"
}

variable "region" {
  description = "The region to host the cluster in"
}

variable "network" {
  description = "The VPC network created to host the cluster in"
}

variable "subnetwork" {
  description = "The subnetwork created to host the cluster in"
}

variable "ip_range_pods_name" {
  description = "The secondary ip range to use for pods"
  default     = "ip-range-pods"
}

variable "ip_range_services_name" {
  description = "The secondary ip range to use for services"
  default     = "ip-range-svc"
}

variable "zones" {
  type        = list(string)
  description = "The zone to host the cluster in (required if is a zonal cluster)"
}

variable "cluster_name_suffix" {
  description = "A suffix to append to the default cluster name"
}

variable "compute_engine_service_account" {
  description = "Service account to associate to the nodes in the cluster"
}

variable "cluster_autoscaling" {
  type = object({
    enabled             = bool
    autoscaling_profile = string
    min_cpu_cores       = number
    max_cpu_cores       = number
    min_memory_gb       = number
    max_memory_gb       = number
    gpu_resources = list(object({
      resource_type = string
      minimum       = number
      maximum       = number
    }))
    auto_repair  = bool
    auto_upgrade = bool
  })
  default = {
    enabled             = true
    autoscaling_profile = "BALANCED"
    max_cpu_cores       = 0
    min_cpu_cores       = 0
    max_memory_gb       = 0
    min_memory_gb       = 0
    gpu_resources       = []
    auto_repair         = true
    auto_upgrade        = true
  }
  description = "Cluster autoscaling configuration. See [more details](https://cloud.google.com/kubernetes-engine/docs/reference/rest/v1beta1/projects.locations.clusters#clusterautoscaling)"
}



variable "argocd" {
  description = "argocd configuration values"
  type = object({
    # credential = string
    namespace = string
    app = object({
      name             = string
      version          = string
      chart            = string
      force_update     = bool
      wait             = bool
      recreate_pods    = bool
      deploy           = bool
      create_namespace = bool
    })
  })
}


variable "argocd_apps" {
  description = "argocd application configuration values"
  type = object({
    namespace = string
    app = object({
      name             = string
      version          = string
      chart            = string
      force_update     = bool
      wait             = bool
      recreate_pods    = bool
      deploy           = bool
      create_namespace = bool
    })
  })
}