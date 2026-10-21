# =============================================================================
# Cloudflare zone wiring — spec 0001 FR-5 and FR-7
#
# Three jobs:
#   1. Point a proxied hostname at the Cloud Run origin.
#   2. Rewrite the Host header so Cloud Run actually answers (see below).
#   3. Inject the shared secret the origin checks, so the edge cannot be
#      bypassed.
#
# >>> PROVIDER VERSION NOTE <<<
# Written for Cloudflare provider v5 and schema-validated against 5.28.1 with
# `tofu validate`. v5 renamed and restructured much of this surface relative to
# v4: cloudflare_record became cloudflare_dns_record, and rules are now a list
# of objects rather than repeated blocks. Do not copy v4 examples found online.
# The schema is verified; runtime behaviour is not, since no zone exists yet.
# =============================================================================

# ── 1. Proxied record ────────────────────────────────────────────────────────
resource "cloudflare_dns_record" "app" {
  zone_id = var.zone_id
  name    = var.subdomain
  type    = "CNAME"
  content = var.origin_hostname
  ttl     = 1    # 1 = automatic, required when proxied
  proxied = true # orange cloud: this is what puts Cloudflare in the path
}

# ── 2. Host header override ──────────────────────────────────────────────────
#
# The gotcha that costs everyone an afternoon. Cloud Run routes requests by
# Host header. A proxied CNAME sends Cloudflare the visitor's Host
# (demo.example.com), which matches no Cloud Run service, so the origin answers
# 404 and it looks like DNS is broken.
#
# Fix: an origin rule rewriting Host to the *.run.app hostname. The visitor
# still sees their own hostname; only the origin-facing request is rewritten.
resource "cloudflare_ruleset" "origin" {
  zone_id = var.zone_id
  name    = "origin-host-rewrite"
  kind    = "zone"
  phase   = "http_request_origin"

  rules = [{
    ref         = "host_header_override"
    description = "Rewrite Host to the Cloud Run hostname so the origin matches the service"
    expression  = "(http.host eq \"${var.hostname}\")"
    action      = "route"
    action_parameters = {
      host_header = var.origin_hostname
    }
    enabled = true
  }]
}

# ── 3. Edge secret injection (FR-7) ──────────────────────────────────────────
#
# Added on the origin-facing request only, so the value never reaches the
# browser. The application rejects anything arriving without it, which is what
# makes "you cannot skip the edge" true for the demo.
#
# Demo-grade by decision: anyone who learns the value can replay it. The
# production recommendation is Cloud Armor allowlisting Cloudflare's ranges.
resource "cloudflare_ruleset" "edge_secret" {
  zone_id = var.zone_id
  name    = "edge-secret-injection"
  kind    = "zone"
  phase   = "http_request_late_transform"

  rules = [{
    ref         = "inject_edge_secret"
    description = "Prove to the origin that this request came through Cloudflare"
    expression  = "(http.host eq \"${var.hostname}\")"
    action      = "rewrite"
    action_parameters = {
      headers = {
        (var.edge_secret_header) = {
          operation = "set"
          value     = var.edge_secret
        }
      }
    }
    enabled = true
  }]
}

# ── TLS ──────────────────────────────────────────────────────────────────────
# TODO(0001): set the zone SSL mode to "full" so the Cloudflare-to-origin leg
# is encrypted. Cloud Run presents a valid Google-managed certificate, so
# "strict" should also work and is worth testing — "flexible" must not be used,
# it would leave the origin leg in plaintext and is indefensible in a security
# demo. Confirm the v5 resource name for zone settings before writing this.
