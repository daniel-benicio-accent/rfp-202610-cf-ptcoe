# =============================================================================
# WAF in front of Juice Shop
#
#   Cloudflare Managed Ruleset     tenant level, every rule on, block
#   Cloudflare OWASP Core Ruleset  zone level, anomaly-scored port of the OWASP CRS
#
# WHY THE MANAGED RULESET RUNS WHOLE
# The first version of this module ran the Cloudflare Managed Ruleset with only
# its `xss` and `lfi` tags switched on, presented as "Managed Rules — XSS
# Protection" and "Managed Rules — LFI Protection". Those protections are no
# longer available, and in the PoC the only managed deployment that worked was
# the Cloudflare Managed Ruleset itself. It now runs with every rule enabled
# and set to block. Finding recorded on 2026-10-29 in specs/0004-waf/spec.md.
#
# WHY TENANT LEVEL
# "Tenant" is the Cloudflare account; the Ruleset Engine has no scope above it.
# The managed ruleset is deployed in the account's entry point (kind = "root"),
# not in the demo zone, so it is not tied to one domain and carries over when
# the demo moves zones. Cloudflare applies account-level managed rulesets to
# Enterprise zones only, and requires the expression to say so: it always ends
# in `cf.zone.plan eq "ENT"`. managed_ruleset_zones narrows it further.
#
# ORDER
# Account-level rulesets run before zone-level ones in the same phase, and a
# block ends evaluation. So the managed ruleset sees every request first and
# OWASP only sees what it let through. Disable the managed ruleset to show
# OWASP catching the same attack.
#
# THE TOGGLES: DISABLE, NEVER DELETE
# Both rulesets are always deployed. enable_waf and the two per-ruleset
# switches only set each execute rule's `enabled` flag, so a switch is an
# in-place update: no ruleset is deleted or recreated, and there is no DNS or
# origin change. Only `tofu destroy` removes the rulesets.
#
# THE GUARDS
#   - the account is not entitled to the Cloudflare Managed Ruleset   -> plan fails
#   - the zone is not entitled to the OWASP Core Ruleset              -> plan fails
#   - the demo zone is not in managed_ruleset_zones                   -> plan warns
#   - the hostname is not proxied (grey cloud)                        -> plan warns
#   - the origin accepts traffic from anywhere                        -> plan warns
#
# An account and a zone each hold one entry point ruleset per phase. If managed
# WAF rules were already deployed in the dashboard, at either level, creating
# these fails with "a similar configuration already exists". The account entry
# point is shared by every zone in the tenant, so manage it from one place only.
#
# >>> PROVIDER VERSION NOTE <<<
# Written for Cloudflare provider v5 and validated against 5.28.1: rules and
# overrides are lists of objects, not repeated blocks as in v4 examples.
# =============================================================================

locals {
  # Fixed, Cloudflare-wide IDs, the same for every account.
  owasp_core_ruleset_id         = "4814384a9e5d4991b9815dcfc25d2f1f"
  cloudflare_managed_ruleset_id = "efb7b8c949ac4650a09736fc376e9aee"
  # The rule inside the OWASP ruleset that acts on the total anomaly score
  # ("949110: Inbound Anomaly Score Exceeded").
  owasp_anomaly_score_rule_id = "6179ae15870a4bb7b2d480d4843b323c"

  # The tenant is the account that owns the demo zone, unless set explicitly.
  account_id = coalesce(var.account_id, data.cloudflare_zone.demo.account.id)

  host_expression = "(http.host eq \"${var.hostname}\")"

  # Account-level scope. No zone list means every Enterprise zone in the tenant.
  managed_zone_filter = length(var.managed_ruleset_zones) > 0 ? "(cf.zone.name in {${join(" ", formatlist("\"%s\"", var.managed_ruleset_zones))}}) and " : ""
  managed_expression  = "${local.managed_zone_filter}(cf.zone.plan eq \"ENT\")"

  managed_enabled = var.enable_waf && var.enable_cloudflare_managed_ruleset
  owasp_enabled   = var.enable_waf && var.enable_owasp_core_ruleset

  # The OWASP ruleset ships with every paranoia level on. A paranoia level is
  # set by switching off the categories above it.
  owasp_disabled_categories = [
    for level in range(var.owasp_paranoia_level + 1, 5) : {
      category = "paranoia-level-${level}"
      enabled  = false
    }
  ]

  account_ruleset_ids = data.cloudflare_rulesets.account.rulesets[*].id
  zone_ruleset_ids    = data.cloudflare_rulesets.zone.rulesets[*].id
}

data "cloudflare_zone" "demo" {
  zone_id = var.zone_id
}

# Every ruleset the account and the zone can use, managed ones included. One
# without the entitlement simply does not list it.
data "cloudflare_rulesets" "account" {
  account_id = local.account_id
}

data "cloudflare_rulesets" "zone" {
  zone_id = var.zone_id
}

# ── Tenant level: Cloudflare Managed Ruleset ─────────────────────────────────

resource "cloudflare_ruleset" "tenant_managed" {
  account_id  = local.account_id
  name        = "tenant-managed-waf"
  description = "Cloudflare Managed Ruleset for the tenant's Enterprise zones, every rule on"
  kind        = "root"
  phase       = "http_request_firewall_managed"

  rules = [
    {
      ref         = "cloudflare_managed_ruleset"
      description = "Cloudflare Managed Ruleset, all rules, ${var.managed_rules_action}"
      expression  = local.managed_expression
      action      = "execute"
      action_parameters = {
        id = local.cloudflare_managed_ruleset_id
        # Ruleset-wide overrides: switches on the rules Cloudflare ships
        # disabled too, and makes every rule act rather than log.
        overrides = {
          enabled = true
          action  = var.managed_rules_action
        }
      }
      enabled = local.managed_enabled
    },
  ]

  lifecycle {
    precondition {
      condition     = contains(local.account_ruleset_ids, local.cloudflare_managed_ruleset_id)
      error_message = "Account ${local.account_id} has no access to the Cloudflare Managed Ruleset at account level. Account-level WAF needs an Enterprise plan with account-level WAF, and a token with the Account WAF Edit permission on that account."
    }
  }
}

# ── Zone level: Cloudflare OWASP Core Ruleset ────────────────────────────────

resource "cloudflare_ruleset" "zone_owasp" {
  zone_id     = var.zone_id
  name        = "wafdemo-owasp-waf"
  description = "OWASP Core Ruleset for the Juice Shop demo hostname"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules = [
    {
      ref         = "owasp_core_ruleset"
      description = "Cloudflare OWASP Core Ruleset, PL${var.owasp_paranoia_level}, threshold ${var.owasp_score_threshold}, ${var.owasp_action}"
      expression  = local.host_expression
      action      = "execute"
      action_parameters = {
        id = local.owasp_core_ruleset_id
        overrides = {
          categories = local.owasp_disabled_categories
          rules = [{
            id              = local.owasp_anomaly_score_rule_id
            action          = var.owasp_action
            score_threshold = var.owasp_score_threshold
          }]
        }
      }
      enabled = local.owasp_enabled
    },
  ]

  lifecycle {
    precondition {
      condition     = contains(local.zone_ruleset_ids, local.owasp_core_ruleset_id)
      error_message = "Zone ${var.zone_id} has no access to the Cloudflare OWASP Core Ruleset. It needs a Pro plan or higher, and a token with Zone WAF permission."
    }
  }
}

# ── Guards that warn rather than fail ────────────────────────────────────────
# Check blocks report a failed assertion as a warning on plan and apply. They
# never stop the run, so they also cover the moment the WAF is switched off.

# The Enterprise half of the scope (cf.zone.plan eq "ENT") is not checked here:
# the zone's plan attribute is deprecated in provider v5. The runbook's
# pre-flight call prints the plan instead.
check "demo_zone_in_managed_scope" {
  assert {
    condition     = !local.managed_enabled || length(var.managed_ruleset_zones) == 0 || contains(var.managed_ruleset_zones, data.cloudflare_zone.demo.name)
    error_message = "Zone ${data.cloudflare_zone.demo.name} is not in managed_ruleset_zones, so the tenant-level Cloudflare Managed Ruleset never inspects it. Add it to the list, or empty the list to cover every Enterprise zone in the account."
  }
}

check "hostname_is_proxied" {
  data "cloudflare_dns_records" "demo" {
    zone_id = var.zone_id
    name = {
      exact = var.hostname
    }
  }

  assert {
    condition     = !var.enable_waf || anytrue([for r in data.cloudflare_dns_records.demo.result : r.proxied])
    error_message = "${var.hostname} is not a proxied record, so its traffic never reaches the WAF. Apply the zone module with proxied = true."
  }
}

check "origin_is_locked_to_cloudflare" {
  data "terraform_remote_state" "gcp" {
    backend = "local"
    config = {
      path = "${path.module}/../../gcp/terraform.tfstate"
    }
  }

  assert {
    condition     = !var.enable_waf || try(data.terraform_remote_state.gcp.outputs.origin_locked_to_cloudflare, false)
    error_message = "The origin VM still accepts traffic from anywhere, so the WAF can be bypassed by going to its IP. Set lock_origin_to_cloudflare = true in the gcp module and apply."
  }
}
