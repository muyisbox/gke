# ============================================================
# GKE custom ComputeClasses
#
# A ComputeClass is a priority-ordered list of node shapes. When a Pod cannot
# be scheduled, the autoscaler walks the list and provisions the first shape it
# can get, instead of node auto-provisioning inferring a shape from Pod
# requests. That makes "what does a scale-up look like" a reviewable file
# rather than an emergent property of the cluster.
#
# The CRD is installed and managed by GKE itself (1.30.3-gke.1451000+ with node
# auto-provisioning on, both of which this cluster has), so Terraform only
# applies the custom resources.
# ============================================================

locals {
  # yamlencode emits explicit nulls, and the API server rejects a ComputeClass
  # carrying e.g. `machineType: null`. Every optional field is therefore dropped
  # before encoding rather than passed through as null.
  compute_class_priorities = {
    for name, cc in var.compute_classes : name => [
      for p in cc.priorities : {
        for k, v in {
          machineFamily = p.machine_family
          machineType   = p.machine_type
          spot          = p.spot
          minCores      = p.min_cores
          minMemoryGb   = p.min_memory_gb
          storage = p.storage == null ? null : one([
            for pruned in [{
              for sk, sv in {
                bootDiskType  = p.storage.boot_disk_type
                bootDiskSize  = p.storage.boot_disk_size
                localSSDCount = p.storage.local_ssd_count
              } : sk => sv if sv != null
            }] : pruned if length(pruned) > 0
          ])
        } : k => v if v != null
      }
    ]
  }

  compute_class_specs = {
    for name, cc in var.compute_classes : name => merge(
      {
        priorities           = local.compute_class_priorities[name]
        nodePoolAutoCreation = { enabled = cc.node_pool_auto_creation }
        whenUnsatisfiable    = cc.when_unsatisfiable
      },
      cc.active_migration == null ? {} : {
        activeMigration = {
          for k, v in {
            optimizeRulePriority          = cc.active_migration.optimize_rule_priority
            ensureAllDaemonSetPodsRunning = cc.active_migration.ensure_all_daemonset_pods_running
          } : k => v if v != null
        }
      },
      cc.autoscaling_policy == null ? {} : {
        autoscalingPolicy = {
          for k, v in {
            consolidationDelayMinutes = cc.autoscaling_policy.consolidation_delay_minutes
            consolidationThreshold    = cc.autoscaling_policy.consolidation_threshold
          } : k => v if v != null
        }
      },
    )
  }
}

resource "kubectl_manifest" "compute_class" {
  for_each          = var.compute_classes
  server_side_apply = true

  yaml_body = yamlencode({
    apiVersion = "cloud.google.com/v1"
    kind       = "ComputeClass"
    metadata = {
      name = each.key
      labels = {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = local.compute_class_specs[each.key]
  })

  depends_on = [module.gke]
}
