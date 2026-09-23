resource "helm_release" "this" {
  count = var.app.deploy ? 1 : 0

  name       = var.app.name
  chart      = var.app.chart
  version    = var.app.version
  namespace  = var.namespace
  repository = var.repository

  repository_key_file  = var.repository_config.repository_key_file
  repository_cert_file = var.repository_config.repository_cert_file
  repository_ca_file   = var.repository_config.repository_ca_file
  repository_username  = var.repository_config.repository_username
  repository_password  = var.repository_config.repository_password

  atomic                     = var.app.atomic
  cleanup_on_fail            = var.app.cleanup_on_fail
  create_namespace           = var.app.create_namespace
  dependency_update          = var.app.dependency_update
  disable_openapi_validation = var.app.disable_openapi_validation
  disable_webhooks           = var.app.disable_webhooks
  force_update               = var.app.force_update
  lint                       = var.app.lint
  max_history                = var.app.max_history
  recreate_pods              = var.app.recreate_pods
  render_subchart_notes      = var.app.render_subchart_notes
  replace                    = var.app.replace
  reset_values               = var.app.reset_values
  reuse_values               = var.app.reuse_values
  skip_crds                  = var.app.skip_crds
  verify                     = var.app.verify
  wait                       = var.app.wait
  wait_for_jobs              = var.app.wait_for_jobs

  values        = var.values
  set           = var.set
  set_sensitive = var.set_sensitive
}
