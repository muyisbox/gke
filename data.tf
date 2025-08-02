data "google_client_config" "default" {}

data "google_container_engine_versions" "gke-version" {
  project        = var.project_id
  location       = "us-central1"
  version_prefix = "1.32."
}