output "hostname" {
  description = "Public hostname served through Cloudflare."
  value       = var.hostname
}

output "edge_secret_header" {
  description = "Header name the origin must check (spec 0001 FR-7)."
  value       = var.edge_secret_header
}
