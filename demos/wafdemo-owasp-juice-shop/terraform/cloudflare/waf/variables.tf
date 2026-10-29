variable "zone_id" {
  description = "Cloudflare zone ID for the demo domain. Also identifies the tenant (account) unless account_id is set."
  type        = string
}

variable "hostname" {
  description = "Public hostname the zone-level OWASP rule applies to."
  type        = string
}

variable "account_id" {
  description = "Cloudflare account (tenant) whose entry point holds the managed ruleset. Null uses the account that owns zone_id."
  type        = string
  default     = null
}

variable "enable_waf" {
  description = <<-EOT
    The WAF switch. Off by default so the demo can show the baseline first,
    then switch it on and repeat the same requests. Off disables both rules
    in place; it never deletes a ruleset.
  EOT
  type        = bool
  default     = false
}

variable "enable_cloudflare_managed_ruleset" {
  description = "Tenant-level Cloudflare Managed Ruleset, while enable_waf is on. false disables its rule; the ruleset stays deployed."
  type        = bool
  default     = true
}

variable "enable_owasp_core_ruleset" {
  description = "Zone-level Cloudflare OWASP Core Ruleset, while enable_waf is on. false disables its rule; the ruleset stays deployed."
  type        = bool
  default     = true
}

variable "managed_ruleset_zones" {
  description = <<-EOT
    Zone names the tenant-level managed ruleset applies to. Empty means every
    Enterprise zone in the account, which in a shared tenant includes zones
    that are not part of this demo.
  EOT
  type        = list(string)
  default     = []
}

variable "managed_rules_action" {
  description = <<-EOT
    Action for every rule in the Cloudflare Managed Ruleset. block by
    decision; the other values are there for the challenge-versus-block
    conversation, not for the committed demo.
  EOT
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "managed_challenge", "js_challenge", "log"], var.managed_rules_action)
    error_message = "managed_rules_action must be one of: block, managed_challenge, js_challenge, log."
  }
}

variable "owasp_paranoia_level" {
  description = <<-EOT
    OWASP Core Ruleset paranoia level, 1-4. Higher catches more and blocks
    more legitimate traffic. 1 suits a JSON-heavy single-page app like Juice
    Shop; raise it only to make a point about false positives.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 3, 4], var.owasp_paranoia_level)
    error_message = "owasp_paranoia_level must be 1, 2, 3 or 4."
  }
}

variable "owasp_score_threshold" {
  description = "Anomaly score at which the OWASP ruleset acts: 25 = high sensitivity, 40 = medium, 60 = low."
  type        = number
  default     = 40

  validation {
    condition     = contains([25, 40, 60], var.owasp_score_threshold)
    error_message = "owasp_score_threshold must be 25, 40 or 60."
  }
}

variable "owasp_action" {
  description = "What the OWASP ruleset does when the threshold is reached. log is Enterprise only."
  type        = string
  default     = "block"

  validation {
    condition     = contains(["block", "managed_challenge", "js_challenge", "log"], var.owasp_action)
    error_message = "owasp_action must be one of: block, managed_challenge, js_challenge, log."
  }
}
