variable "zone_id" {
  description = "Cloudflare zone ID for the demo domain."
  type        = string
}

variable "subdomain" {
  description = "Record name within the zone, e.g. \"demo\"."
  type        = string
}

variable "hostname" {
  description = "Full public hostname, e.g. \"demo.example.com\". Must match subdomain + zone."
  type        = string
}

variable "origin_hostname" {
  description = <<-EOT
    Cloud Run hostname without the scheme, e.g. "myenv-abc123-ew.a.run.app".
    Derive it from the gcp module's service_url output.
  EOT
  type        = string
}

variable "edge_secret" {
  description = <<-EOT
    Shared secret injected towards the origin (spec 0001 FR-7). Supplied
    through TF_VAR_edge_secret; never written to a tracked file.
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
  description = "Header name carrying the edge secret. Must match what the app checks."
  type        = string
  default     = "X-Edge-Auth"
}
