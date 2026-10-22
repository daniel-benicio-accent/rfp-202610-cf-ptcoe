variable "project_id" {
  description = "The GCP project ID where the origin is deployed."
  type        = string
}

variable "region" {
  description = "The GCP region for Artifact Registry, Cloud Run and Firestore."
  type        = string
  default     = "europe-west1"
}

variable "app_name" {
  description = "Environment / application name used for resource naming."
  type        = string
}

variable "audit_bucket" {
  description = <<-EOT
    Cloud Storage bucket for the audit log sink. Created OUTSIDE Terraform on
    purpose, so it survives `tofu destroy` and keeps the evidence trail for
    every environment that ever existed. See spec 0001 FR-12.
  EOT
  type        = string
}

variable "submitter" {
  description = <<-EOT
    IAM member running `gcloud builds submit`, e.g. "user:someone@example.com".
    Needs resource-scoped roles on the app service account — see the comment on
    google_service_account_iam_member in main.tf.
  EOT
  type        = string
}

variable "edge_secret" {
  description = <<-EOT
    Shared secret that Cloudflare injects as a request header and the origin
    checks, so the edge cannot be bypassed (spec 0001 FR-7). Supplied through
    TF_VAR_edge_secret; never written to a tracked file.
  EOT
  type        = string
  sensitive   = true

  validation {
    # The origin falls back to accepting direct traffic when EDGE_SECRET is
    # empty, so an empty or trivial value would silently defeat FR-7. Catch it
    # at plan time instead of discovering it mid-demo.
    condition     = length(var.edge_secret) >= 16
    error_message = "edge_secret must be at least 16 characters. Generate one with: openssl rand -hex 24"
  }
}

variable "edge_secret_header" {
  description = <<-EOT
    Header carrying the edge secret. Must match the zone module's value of the
    same name, otherwise Cloudflare sets one header and the origin checks a
    different one — which fails closed, so every request 403s.
  EOT
  type        = string
  default     = "X-Edge-Auth"
}
