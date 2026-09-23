variable "namespace" {
  description = "Namespace to deploy the release into."
  type        = string
}

variable "repository" {
  description = "Helm repository URL."
  type        = string
}

variable "app" {
  description = "The release. Only name and chart are required; every other attribute falls back to the helm provider's own default."

  type = object({
    name    = string
    chart   = string
    version = optional(string)

    # deploy = false keeps the module in the graph (so outputs and depends_on
    # still resolve) without creating a release.
    deploy = optional(bool, true)

    atomic                     = optional(bool, false)
    cleanup_on_fail            = optional(bool, false)
    create_namespace           = optional(bool, false)
    dependency_update          = optional(bool, false)
    disable_openapi_validation = optional(bool, false)
    disable_webhooks           = optional(bool, false)
    force_update               = optional(bool, true)
    lint                       = optional(bool, true)
    max_history                = optional(number, 0)
    recreate_pods              = optional(bool, true)
    render_subchart_notes      = optional(bool, true)
    replace                    = optional(bool, false)
    reset_values               = optional(bool, false)
    reuse_values               = optional(bool, false)
    skip_crds                  = optional(bool, false)
    verify                     = optional(bool, false)
    wait                       = optional(bool, true)
    wait_for_jobs              = optional(bool, false)
  })
}

variable "repository_config" {
  description = "Credentials and TLS material for a private Helm repository."

  type = object({
    repository_key_file  = optional(string)
    repository_cert_file = optional(string)
    repository_ca_file   = optional(string)
    repository_username  = optional(string)
    repository_password  = optional(string)
  })

  default   = {}
  sensitive = true
}

variable "values" {
  description = "Raw YAML value documents, merged left to right."
  type        = list(string)
  default     = []
}

variable "set" {
  description = "Individual values merged over var.values, equivalent to helm --set."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "set_sensitive" {
  description = "Like var.set, but kept out of the plan diff."
  type = list(object({
    name  = string
    value = string
  }))
  default   = []
  sensitive = true
}
