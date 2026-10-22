terraform {
  required_version = ">= 1.5"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

# Authenticates from CLOUDFLARE_API_TOKEN in the environment.
# Never put the token in a tracked file.
provider "cloudflare" {}
