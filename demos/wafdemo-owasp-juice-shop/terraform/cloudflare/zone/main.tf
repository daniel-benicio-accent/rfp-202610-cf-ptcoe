# =============================================================================
# Cloudflare zone wiring for the Juice Shop origin
#
# Two jobs:
#   1. An A record for the hostname, pointing at the VM's static IP.
#   2. The edge-to-origin TLS mode, for this hostname only.
#
# No Host rewrite and no edge secret, unlike the Cloud Run demo: nginx on the
# VM answers any Host, and origin lockdown is done by the VPC firewall
# (gcp module, lock_origin_to_cloudflare) rather than by a shared header.
#
# >>> PROVIDER VERSION NOTE <<<
# Written for Cloudflare provider v5. v4 examples found online (cloudflare_record,
# repeated rules blocks) will not apply.
# =============================================================================

# ── 1. Record ────────────────────────────────────────────────────────────────
resource "cloudflare_dns_record" "origin" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "A"
  content = var.origin_ip
  ttl     = 1 # automatic; required when proxied
  proxied = var.proxied
  comment = "wafdemo-owasp-juice-shop origin (managed by Terraform)"
}

# ── 2. Origin TLS mode, scoped to this hostname ──────────────────────────────
# A configuration rule rather than the zone's SSL setting, because the zone
# setting applies to every other hostname in the zone too.
#
# A zone holds one ruleset per phase. If http_config_settings already has
# rules created in the dashboard, this fails with "a similar configuration
# already exists" — import that ruleset or move its rules here.
resource "cloudflare_ruleset" "origin_ssl" {
  zone_id = var.zone_id
  name    = "wafdemo-origin-ssl"
  kind    = "zone"
  phase   = "http_config_settings"

  rules = [{
    ref         = "origin_ssl_mode"
    description = "Encrypt the Cloudflare-to-origin leg for the Juice Shop hostname"
    expression  = "(http.host eq \"${var.hostname}\")"
    action      = "set_config"
    action_parameters = {
      ssl = var.origin_ssl_mode
    }
    enabled = true
  }]
}
