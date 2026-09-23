output "deployment" {
  description = "Metadata of the deployed release, or null when var.app.deploy is false."
  value       = one(helm_release.this[*].metadata)
}
