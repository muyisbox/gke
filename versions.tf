terraform {
  required_version = ">= 1.9"

  backend "gcs" {
    bucket = "cluster-dreams-terraform"
    prefix = "terraform/state"
  }

  required_providers {
    # Upper bound is not cosmetic: terraform-google-modules/kubernetes-engine
    # v45 declares ">= 7.39.0, < 8". Raising this to 8.x will fail `init` until
    # the GKE module publishes a release that supports it.
    google = {
      source  = "hashicorp/google"
      version = ">= 7.39.0, < 8.0"
    }
    # Not used directly, but the shared-network module is. Without this pin it
    # floats to 8.x while google stays on 7.x, which puts two different schema
    # generations behind the same resources.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.39.0, < 8.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
    # Applies raw YAML (ESO CRDs + CRs) that has no first-class resource in the
    # kubernetes provider. kubernetes_manifest is not a substitute here: it
    # requires a reachable API server at plan time, which breaks the nightly
    # destroy/recreate cycle.
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    # Used only for the destroy-ordering barrier in shared-network.tf.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}
