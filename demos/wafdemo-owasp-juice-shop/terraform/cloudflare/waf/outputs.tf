output "enabled" {
  description = "Whether the WAF switch is on."
  value       = var.enable_waf
}

output "tenant_ruleset_id" {
  description = "ID of the account entry point ruleset that holds the Cloudflare Managed Ruleset."
  value       = cloudflare_ruleset.tenant_managed.id
}

output "zone_ruleset_id" {
  description = "ID of the zone entry point ruleset that holds the OWASP Core Ruleset."
  value       = cloudflare_ruleset.zone_owasp.id
}

output "cloudflare_managed_ruleset" {
  description = "Tenant-level Cloudflare Managed Ruleset as deployed. enabled is the effective state of its rule."
  value = {
    enabled    = local.managed_enabled
    account_id = local.account_id
    expression = local.managed_expression
    action     = var.managed_rules_action
  }
}

output "owasp_core_ruleset" {
  description = "Zone-level OWASP Core Ruleset as deployed. enabled is the effective state of its rule."
  value = {
    enabled         = local.owasp_enabled
    paranoia_level  = var.owasp_paranoia_level
    score_threshold = var.owasp_score_threshold
    action          = var.owasp_action
  }
}

output "verify_command" {
  description = "Reads both entry points back from the Cloudflare API: one line per rule, in evaluation order (account first, then zone). Needs jq."
  value       = "for scope in accounts/${local.account_id} zones/${var.zone_id}; do curl -s -H \"Authorization: Bearer $CLOUDFLARE_API_TOKEN\" \"https://api.cloudflare.com/client/v4/$scope/rulesets/phases/http_request_firewall_managed/entrypoint\" | jq -r --arg scope \"$${scope%%/*}\" '.result.rules[] | [$scope, .enabled, .action_parameters.id, .description] | @tsv'; done"
}
