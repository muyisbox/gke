# ============================================================
# Velero — GCP side
#
# The Velero chart itself is deployed by ArgoCD (gke-applications/*/velero.yaml).
# Those app definitions reference a bucket and a Workload Identity service
# account that nothing was creating; this file owns them.
#
# The bucket and identity are project-wide, so only the hub workspace creates
# them. The Workload Identity member string is bound to the project's identity
# pool rather than to one cluster, so a single binding covers velero/velero on
# every cluster in the project.
# ============================================================

locals {
  velero_enabled  = local.is_gitops && var.velero.enabled
  velero_bucket   = coalesce(var.velero.bucket_name, "${var.project_id}-velero-backups")
  velero_location = coalesce(var.velero.bucket_location, upper(var.region))
}

resource "google_storage_bucket" "velero" {
  count = local.velero_enabled ? 1 : 0

  name     = local.velero_bucket
  project  = var.project_id
  location = local.velero_location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Velero prunes expired backups itself; this is the backstop for objects it
  # loses track of (for example after a cluster is deleted mid-backup).
  lifecycle_rule {
    condition {
      age = var.velero.retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    managed-by = "terraform"
    purpose    = "velero-backups"
  }
}

resource "google_service_account" "velero" {
  count        = local.velero_enabled ? 1 : 0
  account_id   = var.velero.service_account_id
  display_name = "Velero Controller - Workload Identity"
  project      = var.project_id
}

# Scoped to the backup bucket rather than a project-wide storage role.
resource "google_storage_bucket_iam_member" "velero" {
  count  = local.velero_enabled ? 1 : 0
  bucket = google_storage_bucket.velero[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.velero[0].email}"
}

# Needed for volumeSnapshotLocation: Velero creates and deletes PD snapshots.
resource "google_project_iam_member" "velero_compute" {
  for_each = local.velero_enabled ? toset([
    "roles/compute.storageAdmin",
    "roles/iam.serviceAccountUser",
  ]) : toset([])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.velero[0].email}"
}

resource "google_service_account_iam_member" "velero_workload_identity" {
  count              = local.velero_enabled ? 1 : 0
  service_account_id = google_service_account.velero[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.velero.kubernetes_namespace}/velero]"
}
