terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
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
