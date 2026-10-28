variable "zone_id" {
  description = "Cloudflare zone ID for the demo domain."
  type        = string
}

variable "hostname" {
  description = "Public hostname the WAF applies to. Every rule is scoped to it."
  type        = string
}

variable "enable_waf" {
  description = <<-EOT
    The WAF switch. Off by default so the demo can show the baseline first,
    then switch it on and repeat the same requests.
  EOT
  type        = bool
  default     = false
}

variable "enable_xss_protection" {
  description = "Managed Rules — XSS Protection: the Cloudflare Managed Ruleset's XSS rules."
  type        = bool
  default     = true
}

variable "enable_lfi_protection" {
  description = "Managed Rules — LFI Protection: the Cloudflare Managed Ruleset's local file inclusion rules."
  type        = bool
  default     = true
}

variable "xss_category" {
  description = "Tag that marks XSS rules in the Cloudflare Managed Ruleset. The plan checks it against the live ruleset and suggests the right one if it is wrong."
  type        = string
  default     = "xss"
}

variable "lfi_category" {
  description = "Tag that marks LFI rules in the Cloudflare Managed Ruleset. Checked the same way as xss_category."
  type        = string
  default     = "lfi"
}

variable "managed_rules_action" {
  description = <<-EOT
    Action for the XSS and LFI rules. Set explicitly because switching a tag
    on also switches on rules Cloudflare ships disabled or in log mode, and
    "protection" should mean they act.
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
