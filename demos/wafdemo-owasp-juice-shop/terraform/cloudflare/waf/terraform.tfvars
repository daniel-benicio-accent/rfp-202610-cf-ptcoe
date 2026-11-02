zone_id  = "de34e22a6e43608162ec40acd6112b7c"
hostname = "coedemo.dbenicio.com"

# Off for the baseline. Switch on from the command line during the demo:
#   tofu apply -var 'enable_waf=true'
# Off disables the rules in place; the rulesets stay deployed. Enabling and
# disabling the managed ruleset on its own: Rollout notes in
# specs/0004-waf/plan.md.
enable_waf = false

# Tenant-level Cloudflare Managed Ruleset: every rule on, block. An empty zone
# list means every Enterprise zone in the account; to keep it to this demo,
# list the zone instead, e.g. ["<demo-zone>"].
enable_cloudflare_managed_ruleset = true
managed_ruleset_zones             = []
managed_rules_action              = "block"

# Zone-level OWASP Core Ruleset. See variables.tf.
enable_owasp_core_ruleset = true
owasp_paranoia_level      = 1
owasp_score_threshold     = 40
owasp_action              = "block"
