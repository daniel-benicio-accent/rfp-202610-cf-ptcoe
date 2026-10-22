output "enabled" {
  description = "Whether Bot management is currently switched on."
  value       = var.enable_bot_management
}

output "ruleset_id" {
  description = "Ruleset ID, or null when the feature is disabled."
  value       = try(cloudflare_ruleset.this[0].id, null)
}
