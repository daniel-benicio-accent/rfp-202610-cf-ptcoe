variable "zone_id" {
  description = "Cloudflare zone ID for the demo domain."
  type        = string
}

variable "hostname" {
  description = "Public hostname this feature applies to. Scope expressions to it."
  type        = string
}

variable "enable_bot_management" {
  description = <<-EOT
    Switch for Bot management (spec 0002). Off by default so a demo
    can establish the baseline first, then enable the feature and re-run the
    same traffic (spec 0001 FR-6).
  EOT
  type        = bool
  default     = false
}

variable "phase" {
  description = "Ruleset phase. See the table in main.tf."
  type        = string
  # TODO(0002): set the phase this feature belongs in.
}

variable "expression" {
  description = "Cloudflare rule expression deciding what this feature matches."
  type        = string
  # TODO(0002): no default on purpose — an unscoped rule could affect
  # the whole zone, so every caller must state what it matches.
}

variable "action" {
  description = "What to do on a match, e.g. block, managed_challenge, js_challenge, log."
  type        = string
  default     = "block"

  validation {
    condition = contains(
      ["block", "managed_challenge", "js_challenge", "log", "skip"],
      var.action
    )
    error_message = "action must be one of: block, managed_challenge, js_challenge, log, skip."
  }
}
