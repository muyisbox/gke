data "google_client_config" "default" {}

data "google_project" "current" {
  project_id = var.project_id
}
