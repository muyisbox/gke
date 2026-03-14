output "deployment" {
  value = var.app["deploy"] ? helm_release.this[0].metadata : {
    app_version    = ""
    chart          = ""
    first_deployed = 0
    last_deployed  = 0
    name           = ""
    namespace      = ""
    notes          = ""
    revision       = 0
    values         = ""
    version        = ""
  }
  description = "The state of the helm deployment"
}