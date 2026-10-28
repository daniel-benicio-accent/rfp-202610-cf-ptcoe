output "enabled" {
  description = "Whether the WAF is currently switched on."
  value       = var.enable_waf
}

output "ruleset_id" {
  description = "Ruleset ID, or null when the WAF is off."
  value       = try(cloudflare_ruleset.waf[0].id, null)
}

output "owasp_core_ruleset" {
  description = "OWASP Core Ruleset settings as deployed, or null when the WAF is off."
  value = var.enable_waf ? {
    paranoia_level  = var.owasp_paranoia_level
    score_threshold = var.owasp_score_threshold
    action          = var.owasp_action
  } : null
}

output "managed_protections" {
  description = "Managed Rules protections in force, by requirement name, with the Cloudflare Managed Ruleset tag each one maps to. Empty when the WAF is off."
  value       = var.enable_waf ? local.managed_enabled : {}
}

output "verify_command" {
  description = "Reads the live ruleset back from the Cloudflare API: one line per rule, in evaluation order. Needs jq."
  value       = "curl -s -H \"Authorization: Bearer $CLOUDFLARE_API_TOKEN\" https://api.cloudflare.com/client/v4/zones/${var.zone_id}/rulesets/phases/http_request_firewall_managed/entrypoint | jq -r '.result.rules[] | [.enabled, .action_parameters.id, .description] | @tsv'"
}
