variable "zone_id" {
  description = "Cloudflare zone ID for the demo domain."
  type        = string
}

variable "hostname" {
  description = "Full public hostname, e.g. \"demo.example.com\". Must sit inside the zone."
  type        = string
}

variable "origin_ip" {
  description = <<-EOT
    Static public IP of the VM. Take it from the gcp module:
      tofu -chdir=../../gcp output -raw public_ip
  EOT
  type        = string

  validation {
    condition     = can(cidrhost("${var.origin_ip}/32", 0))
    error_message = "origin_ip must be an IPv4 address. Fill it in from the gcp module's public_ip output."
  }
}

variable "proxied" {
  description = <<-EOT
    true  = orange cloud: traffic goes through Cloudflare, and the WAF applies.
    false = grey cloud: DNS only, visitors reach the VM directly and no
            Cloudflare protection applies at all.
  EOT
  type        = bool
  default     = true
}

variable "origin_ssl_mode" {
  description = <<-EOT
    How Cloudflare connects to the origin, for this hostname only. "full"
    matches the self-signed certificate the VM generates. Never "flexible": it
    leaves the origin leg in plaintext.
  EOT
  type        = string
  default     = "full"

  validation {
    condition     = contains(["full", "strict"], var.origin_ssl_mode)
    error_message = "origin_ssl_mode must be full or strict."
  }
}
