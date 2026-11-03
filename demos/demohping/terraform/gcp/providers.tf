terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# No default project on purpose: this module creates its own, and every
# resource names it explicitly. Credentials come from Application Default
# Credentials — see docs/prerequisites.md.
provider "google" {
  region = var.region
}

data "google_client_config" "default" {}

# Pointed at the cluster this same module creates, so one apply goes from an
# empty billing account to a serving page. Helm is the only in-cluster
# provider on purpose: the Istio objects (Gateway, VirtualService,
# PeerAuthentication) are CRDs, and the kubernetes provider's manifest
# resource needs those CRDs to exist at plan time, which on a fresh cluster
# they never do. A Helm chart is only rendered at apply time.
provider "helm" {
  kubernetes = {
    host                   = "https://${google_container_cluster.this.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.this.master_auth[0].cluster_ca_certificate)
  }
}
