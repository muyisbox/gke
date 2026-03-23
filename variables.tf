variable "project_id" {
  description = "The project ID to host the cluster in"
}

variable "cluster_name" {
  description = "The name for the GKE cluster"
}

variable "region" {
  description = "The region to host the cluster in"
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
    enabled                      = bool
    enable_default_compute_class = optional(bool, false)
    autoscaling_profile          = string
    min_cpu_cores                = number
    max_cpu_cores                = number
    min_memory_gb                = number
    max_memory_gb                = number
    gpu_resources = list(object({
      resource_type = string
      minimum       = number
      maximum       = number
    }))
    auto_repair  = bool
    auto_upgrade = bool
  })
  default = {
    enabled                      = true
    enable_default_compute_class = false
    autoscaling_profile          = "BALANCED"
    max_cpu_cores                = 0
    min_cpu_cores                = 0
    max_memory_gb                = 0
    min_memory_gb                = 0
    gpu_resources                = []
    auto_repair                  = true
    auto_upgrade                 = true
  }
  description = "Cluster autoscaling configuration. See [more details](https://cloud.google.com/kubernetes-engine/docs/reference/rest/v1beta1/projects.locations.clusters#clusterautoscaling)"
}



variable "environments" {
  description = "Map of environments. Each entry provisions a GKE cluster, subnet, and secondary IP ranges. CIDRs must be unique and stable — changing them forces cluster recreation. To add a new environment, add an entry with non-overlapping CIDRs and the next available master_cidr_offset."
  type = map(object({
    node_cidr          = string
    range_base         = string
    master_cidr_offset = number
  }))
}

variable "eso_version" {
  description = "External Secrets Operator version - used for CRD installation and chart deployment"
  type        = string
  default     = "2.1.0"
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