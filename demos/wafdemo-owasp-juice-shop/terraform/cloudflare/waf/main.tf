# =============================================================================
# WAF in front of Juice Shop
#
#   Managed Rules — XSS Protection   Cloudflare Managed Ruleset, xss rules only
#   Managed Rules — LFI Protection   Cloudflare Managed Ruleset, lfi rules only
#   Cloudflare OWASP Core Ruleset    anomaly-scored port of the OWASP CRS
#
# WHAT "XSS PROTECTION" AND "LFI PROTECTION" ARE
# Cloudflare ships no rulesets by those names. XSS and LFI protection are rule
# tags inside the Cloudflare Managed Ruleset. Here that ruleset is executed with
# every rule switched off, then only the requested tags switched back on. This
# works because tag overrides take precedence over ruleset overrides. Both
# protections share that one execute rule, because Cloudflare does not document
# executing the same managed ruleset twice in one phase.
#
# ORDER
# Rules run in list order and a block ends evaluation. The XSS and LFI rules go
# first: they block on a single match, so XSS and LFI attempts are credited to
# the protections the requirement names. OWASP runs after, on everything still
# standing, and blocks once a request's anomaly score reaches the threshold.
# Swap the two list entries to credit OWASP first instead.
#
# THE TOGGLE
# enable_waf = false deletes the ruleset: the hostname stays proxied, nothing
# inspects it. Same URL before and after, no DNS change.
#
# THE GUARDS
#   - the zone is not entitled to a ruleset in use (Free plan)  -> plan fails
#   - a requested tag does not exist in the managed ruleset     -> plan fails
#   - the hostname is not proxied (grey cloud)                  -> plan warns
#   - the origin accepts traffic from anywhere                  -> plan warns
#
# A zone holds one ruleset per phase. If managed WAF rules were already
# deployed in the dashboard, creating this fails with "a similar configuration
# already exists". Manage this phase from one place only.
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

  host_expression = "(http.host eq \"${var.hostname}\")"

  # The OWASP ruleset ships with every paranoia level on. A paranoia level is
  # set by switching off the categories above it.
  owasp_disabled_categories = [
    for level in range(var.owasp_paranoia_level + 1, 5) : {
      category = "paranoia-level-${level}"
      enabled  = false
    }
  ]

  # Requirement name -> Cloudflare Managed Ruleset tag.
  managed_protections = {
    "XSS Protection" = { enabled = var.enable_xss_protection, category = var.xss_category }
    "LFI Protection" = { enabled = var.enable_lfi_protection, category = var.lfi_category }
  }
  managed_enabled    = { for name, p in local.managed_protections : name => p.category if p.enabled }
  managed_categories = values(local.managed_enabled)

  zone_ruleset_ids = data.cloudflare_rulesets.zone.rulesets[*].id
  managed_entitled = contains(local.zone_ruleset_ids, local.cloudflare_managed_ruleset_id)

  # Tags present in the live Cloudflare Managed Ruleset, to catch a wrong tag
  # name at plan time rather than deploy a rule that matches nothing.
  managed_ruleset_tags = distinct(flatten([
    for r in try(data.cloudflare_ruleset.cloudflare_managed[0].rules, []) : r.categories if r.categories != null
  ]))
  missing_managed_categories = [for c in local.managed_categories : c if !contains(local.managed_ruleset_tags, c)]
  similar_managed_tags = sort([
    for t in local.managed_ruleset_tags : t if can(regex("(?i)xss|script|lfi|inclusion|traversal|file", t))
  ])
}

# Every ruleset the zone can use, managed ones included. A zone without the
# entitlement simply does not list it.
data "cloudflare_rulesets" "zone" {
  zone_id = var.zone_id
}

# Read only when it will be used and the zone may read it, so that a Free zone
# gets the entitlement message below instead of a raw API error.
data "cloudflare_ruleset" "cloudflare_managed" {
  count = var.enable_waf && length(local.managed_categories) > 0 && local.managed_entitled ? 1 : 0

  zone_id = var.zone_id
  id      = local.cloudflare_managed_ruleset_id
}

resource "cloudflare_ruleset" "waf" {
  count = var.enable_waf ? 1 : 0

  zone_id     = var.zone_id
  name        = "wafdemo-owasp-waf"
  description = "XSS, LFI and OWASP managed rules for the Juice Shop demo hostname"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules = [
    {
      ref         = "managed_rules_xss_lfi"
      description = "Managed Rules — ${length(local.managed_enabled) > 0 ? join(", ", keys(local.managed_enabled)) : "none selected"}"
      expression  = local.host_expression
      action      = "execute"
      action_parameters = {
        id = local.cloudflare_managed_ruleset_id
        overrides = {
          enabled = false
          categories = [
            for c in local.managed_categories : {
              category = c
              enabled  = true
              action   = var.managed_rules_action
            }
          ]
        }
      }
      enabled = length(local.managed_categories) > 0
    },
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
      enabled = true
    },
  ]

  lifecycle {
    precondition {
      condition     = contains(local.zone_ruleset_ids, local.owasp_core_ruleset_id)
      error_message = "Zone ${var.zone_id} has no access to the Cloudflare OWASP Core Ruleset. It needs a Pro plan or higher, and a token with Zone WAF permission."
    }

    precondition {
      condition     = length(local.managed_categories) == 0 || local.managed_entitled
      error_message = "Zone ${var.zone_id} has no access to the Cloudflare Managed Ruleset, which carries the XSS and LFI protections. It needs a Pro plan or higher."
    }

    precondition {
      condition     = !local.managed_entitled || length(local.missing_managed_categories) == 0
      error_message = "Tag(s) ${join(", ", local.missing_managed_categories)} not found in the Cloudflare Managed Ruleset. Related tags it does have: ${length(local.similar_managed_tags) > 0 ? join(", ", local.similar_managed_tags) : "none"}. Set xss_category / lfi_category to the right one."
    }
  }
}

# ── Guards that warn rather than fail ────────────────────────────────────────
# Check blocks report a failed assertion as a warning on plan and apply. They
# never stop the run, so they also cover the moment the WAF is switched off.

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
