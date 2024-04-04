terraform {
  backend "gcs" {
    bucket = "terraform-310821"
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source = "hashicorp/google"
      # version = "~> 5.14.0"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      # version = "~> 5.14.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # version = "~> 2.25.0"
    }
    helm = {
      source = "hashicorp/helm"
      # version = "~> 2.12.1"
    }
  }
  required_version = ">= 0.13"
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  }
}
provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

