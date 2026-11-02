output "hostname" {
  description = "Public hostname served through Cloudflare."
  value       = var.hostname
}

output "proxied" {
  description = "Whether Cloudflare is in the path (orange cloud)."
  value       = cloudflare_dns_record.origin.proxied
}

output "record_id" {
  description = "DNS record ID."
  value       = cloudflare_dns_record.origin.id
}
