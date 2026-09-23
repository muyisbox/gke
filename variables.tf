# ---------------------------------------------------------------------------
# Project / location
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project that hosts every cluster and the shared network."
  type        = string
}

variable "region" {
  description = "GCP region for the regional GKE clusters and the shared subnets."
  type        = string
}

variable "zones" {
  description = "Zones within var.region that node pools may schedule into."
  type        = list(string)

  validation {
    condition     = length(var.zones) > 0
    error_message = "At least one zone must be supplied."
  }
}

variable "terraform_service_account" {
  description = "Email of the service account Cloud Build runs Terraform as. Granted container.admin scoped to the workspace's own cluster."
  type        = string
}

# ---------------------------------------------------------------------------
# Topology
# ---------------------------------------------------------------------------

variable "gitops_workspace" {
  description = "Name of the hub workspace. It owns the shared VPC/router/NAT and runs ArgoCD; every other workspace is a spoke."
  type        = string
  default     = "gitops"
}

variable "network_name" {
  description = "Name of the shared VPC. Created by the gitops workspace, read by the spokes."
  type        = string
  default     = "shared-gke-network"
}

variable "master_cidr_supernet" {
  description = "Supernet the per-cluster GKE control-plane /28s are carved out of. Changing this forces recreation of every cluster."
  type        = string
  default     = "172.19.0.0/16"
}

variable "environments" {
  description = <<-EOT
    Map of environments. Each entry provisions a GKE cluster, a subnet, and its
    secondary pod/service ranges. CIDRs must be unique and stable — changing them
    forces cluster recreation. To add an environment, add an entry with
    non-overlapping CIDRs and the next free master_cidr_offset.
  EOT

  type = map(object({
    node_cidr          = string
    range_base         = string
    master_cidr_offset = number
  }))

  validation {
    condition     = alltrue([for cfg in values(var.environments) : can(cidrhost(cfg.node_cidr, 0))])
    error_message = "Every node_cidr must be a valid CIDR block."
  }

  validation {
    condition     = alltrue([for cfg in values(var.environments) : can(cidrhost(cfg.range_base, 0))])
    error_message = "Every range_base must be a valid CIDR block; it is split in half into <env>-pods and <env>-services."
  }

  validation {
    condition = alltrue([
      for cfg in values(var.environments) :
      floor(cfg.master_cidr_offset) == cfg.master_cidr_offset && cfg.master_cidr_offset >= 0 && cfg.master_cidr_offset <= 255
    ])
    error_message = "master_cidr_offset must be a whole number between 0 and 255; it selects a /28 inside master_cidr_supernet."
  }

  validation {
    condition     = length(distinct([for cfg in values(var.environments) : cfg.master_cidr_offset])) == length(var.environments)
    error_message = "master_cidr_offset must be unique per environment; duplicates would give two clusters the same control-plane CIDR."
  }
}

# ---------------------------------------------------------------------------
# Cluster shape
# ---------------------------------------------------------------------------

variable "cluster_autoscaling" {
  description = "Node auto-provisioning limits for the cluster. See https://cloud.google.com/kubernetes-engine/docs/reference/rest/v1beta1/projects.locations.clusters#clusterautoscaling"

  type = object({
    enabled                      = optional(bool, true)
    enable_default_compute_class = optional(bool, true)
    autoscaling_profile          = optional(string, "OPTIMIZE_UTILIZATION")
    min_cpu_cores                = optional(number, 0)
    max_cpu_cores                = optional(number, 48)
    min_memory_gb                = optional(number, 0)
    max_memory_gb                = optional(number, 192)
    disk_size                    = optional(number, 30)
    disk_type                    = optional(string, "pd-standard")
    auto_repair                  = optional(bool, true)
    auto_upgrade                 = optional(bool, true)
    gpu_resources = optional(list(object({
      resource_type = string
      minimum       = number
      maximum       = number
    })), [])
  })

  default = {}
}

variable "release_channel" {
  description = "GKE release channel for control plane and node upgrades."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE, EXTENDED."
  }
}

variable "node_oauth_scopes" {
  description = "OAuth scopes granted to every node pool."
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/compute",
  ]
}

# ---------------------------------------------------------------------------
# Node autoscaling
# ---------------------------------------------------------------------------

variable "compute_classes" {
  description = <<-EOT
    GKE custom ComputeClasses, rendered as cloud.google.com/v1 ComputeClass
    objects. Each one is a priority-ordered fallback list telling the node
    autoscaler what shape of node to create, so capacity decisions live in Git
    instead of in whatever NAP happens to pick.

    Pods opt in with a node selector:
      nodeSelector:
        cloud.google.com/compute-class: cost-optimized

    A namespace opts in for every Pod it holds with the label
    cloud.google.com/default-compute-class=<name>.

    The class named "default" is special: because the cluster sets
    enable_default_compute_class, GKE applies it to every Pod that does not
    select another class. Set this map to {} to hand scaling decisions back to
    plain node auto-provisioning.
  EOT

  type = map(object({
    # Tried in order. The first rule GKE can satisfy wins.
    priorities = list(object({
      machine_family = optional(string)
      machine_type   = optional(string)
      spot           = optional(bool)
      min_cores      = optional(number)
      min_memory_gb  = optional(number)
      storage = optional(object({
        boot_disk_type  = optional(string)
        boot_disk_size  = optional(number)
        local_ssd_count = optional(number)
      }))
    }))

    node_pool_auto_creation = optional(bool, true)

    # ScaleUpAnyway falls back to cluster defaults when no rule fits;
    # DoNotScaleUp leaves the Pod pending. The GKE default varies by version,
    # so it is always set explicitly here.
    when_unsatisfiable = optional(string, "ScaleUpAnyway")

    # Moves Pods back onto a higher-priority node shape once one is available.
    # Leave unset for stateful workloads: the node is replaced, not drained
    # into equivalent storage.
    active_migration = optional(object({
      optimize_rule_priority            = optional(bool)
      ensure_all_daemonset_pods_running = optional(bool)
    }))

    # How eagerly underutilised nodes are reclaimed.
    autoscaling_policy = optional(object({
      consolidation_delay_minutes = optional(number)
      consolidation_threshold     = optional(number)
    }))
  }))

  default = {
    # Cluster-wide default. On-demand only: everything unlabelled lands here,
    # including ArgoCD and the monitoring stack.
    default = {
      # min_memory_gb matters more than cores here. Without it, e2-medium
      # satisfies min_cores = 2 with only ~2.8Gi allocatable, and the
      # autoscaler packed the monitoring stack and Loki onto one, where they
      # crash looped. 8Gi lands on e2-standard-2, matching the nodes that
      # stayed healthy.
      priorities = [
        { machine_family = "e2", min_cores = 2, min_memory_gb = 8 },
        { machine_family = "n2", min_cores = 2, min_memory_gb = 8 },
        { machine_family = "n2d", min_cores = 2, min_memory_gb = 8 },
      ]
      autoscaling_policy = {
        consolidation_delay_minutes = 10
        consolidation_threshold     = 70
      }
    }

    # Spot-first with an on-demand floor, so a Pod still schedules when spot
    # capacity is gone. Opt in per workload; expect preemption.
    cost-optimized = {
      priorities = [
        { machine_family = "n2d", spot = true, min_cores = 2 },
        { machine_family = "n2", spot = true, min_cores = 2 },
        { machine_family = "e2", spot = true, min_cores = 2 },
        { machine_family = "e2", spot = false, min_cores = 2 },
      ]
      active_migration = {
        optimize_rule_priority = true
      }
      autoscaling_policy = {
        consolidation_delay_minutes = 5
        consolidation_threshold     = 60
      }
    }

    # Bigger on-demand nodes that are slow to be reclaimed, for the stateful
    # platform add-ons (Prometheus, Loki, ArgoCD). No active migration: these
    # own PVCs and should not be shuffled between nodes to save a few cents.
    platform-critical = {
      priorities = [
        { machine_family = "n2", min_cores = 4, min_memory_gb = 16 },
        { machine_family = "n2d", min_cores = 4, min_memory_gb = 16 },
        { machine_family = "e2", min_cores = 4, min_memory_gb = 16 },
      ]
      autoscaling_policy = {
        consolidation_delay_minutes = 30
        consolidation_threshold     = 50
      }
    }
  }

  validation {
    condition = alltrue([
      for cc in values(var.compute_classes) : contains(["ScaleUpAnyway", "DoNotScaleUp"], cc.when_unsatisfiable)
    ])
    error_message = "when_unsatisfiable must be ScaleUpAnyway or DoNotScaleUp."
  }

  validation {
    condition     = alltrue([for cc in values(var.compute_classes) : length(cc.priorities) > 0])
    error_message = "Each compute class needs at least one priority rule."
  }

  validation {
    condition = alltrue([
      for cc in values(var.compute_classes) : alltrue([
        for p in cc.priorities : p.machine_family != null || p.machine_type != null
      ])
    ])
    error_message = "Each priority rule must set machine_family or machine_type."
  }

  validation {
    condition = alltrue([
      for cc in values(var.compute_classes) :
      cc.autoscaling_policy == null ? true : alltrue([
        cc.autoscaling_policy.consolidation_delay_minutes == null ? true : (
          cc.autoscaling_policy.consolidation_delay_minutes >= 1 && cc.autoscaling_policy.consolidation_delay_minutes <= 1440
        ),
        cc.autoscaling_policy.consolidation_threshold == null ? true : (
          cc.autoscaling_policy.consolidation_threshold >= 0 && cc.autoscaling_policy.consolidation_threshold <= 100
        ),
      ])
    ])
    error_message = "consolidation_delay_minutes must be 1-1440 and consolidation_threshold 0-100."
  }
}

# ---------------------------------------------------------------------------
# Platform add-ons managed by Terraform
# ---------------------------------------------------------------------------

variable "velero" {
  description = "Backing GCP resources for the Velero chart deployed by ArgoCD. bucket_name defaults to <project_id>-velero-backups."
  type = object({
    enabled              = optional(bool, true)
    bucket_name          = optional(string)
    bucket_location      = optional(string)
    retention_days       = optional(number, 30)
    service_account_id   = optional(string, "velero-controller")
    kubernetes_namespace = optional(string, "velero")
  })
  default = {}
}

# Shape shared by both ArgoCD charts. Everything not listed here falls back to
# the modules/helm defaults.
variable "argocd" {
  description = "ArgoCD server chart (deployed by Terraform on the gitops cluster only)."
  type = object({
    namespace = string
    app = object({
      name             = string
      version          = string
      chart            = string
      force_update     = optional(bool, true)
      wait             = optional(bool, false)
      recreate_pods    = optional(bool, false)
      deploy           = optional(bool, true)
      create_namespace = optional(bool, true)
    })
  })
}

variable "argocd_apps" {
  description = "argocd-apps chart: renders the per-cluster AppProjects and ApplicationSets."
  type = object({
    namespace = string
    app = object({
      name             = string
      version          = string
      chart            = string
      force_update     = optional(bool, true)
      wait             = optional(bool, false)
      recreate_pods    = optional(bool, false)
      deploy           = optional(bool, true)
      create_namespace = optional(bool, true)
    })
  })
}

variable "apps_repo_url" {
  description = "Git repository the ArgoCD ApplicationSets read gke-applications/<env>/*.yaml from."
  type        = string
  default     = "https://github.com/muyisbox/gke.git"
}

variable "apps_repo_revision" {
  description = "Git revision the ArgoCD ApplicationSets track."
  type        = string
  default     = "master"
}
