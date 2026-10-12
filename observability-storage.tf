# ============================================================
# Object storage for the hub's telemetry backends
#
# Loki, Tempo and Mimir are deployed by ArgoCD on the gitops cluster
# (gke-applications/gitops/*.yaml). Their data lived on single local PVCs:
# one replica each, lost with the node, zone or cluster, and able to fill.
# GCS makes the hub's history independent of the cluster it runs on.
#
# One bucket and one identity per backend, each scoped to its own bucket,
# bound to that backend's Kubernetes service account by Workload Identity --
# the same pattern as velero.tf. Only the hub workspace creates them.
#
# No age-based lifecycle rule, unlike Velero's: each backend's compactor owns
# retention, and these buckets also hold long-lived metadata that is rarely
# rewritten (Mimir's ruler and Alertmanager state, Loki's index), which an age
# rule would silently delete. Versioning is off for the same reason in
# reverse: every chunk a compactor deletes would otherwise be kept forever.
# ============================================================

locals {
  observability_storage = local.is_gitops ? var.observability_storage.backends : {}
}

resource "google_storage_bucket" "observability" {
  for_each = local.observability_storage

  name     = "${var.project_id}-${each.key}"
  project  = var.project_id
  location = upper(var.region)

  # Without this, destroying the gitops workspace fails on any non-empty bucket.
  force_destroy = true

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    managed-by = "terraform"
    purpose    = "${each.key}-storage"
  }
}

resource "google_service_account" "observability" {
  for_each = local.observability_storage

  account_id   = "${each.key}-storage"
  display_name = "${title(each.key)} object storage - Workload Identity"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "observability" {
  for_each = local.observability_storage

  bucket = google_storage_bucket.observability[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.observability[each.key].email}"
}

# objectAdmin covers objects only. Tempo reads the bucket's own metadata at
# startup (storage.buckets.get) and crash-looped with a 403 without it;
# granted to every backend so Mimir does not hit the same wall.
resource "google_storage_bucket_iam_member" "observability_bucket_metadata" {
  for_each = local.observability_storage

  bucket = google_storage_bucket.observability[each.key].name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.observability[each.key].email}"
}

resource "google_service_account_iam_member" "observability_workload_identity" {
  for_each = local.observability_storage

  service_account_id = google_service_account.observability[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.service_account}]"
}
