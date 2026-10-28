zone_id  = "de34e22a6e43608162ec40acd6112b7c"
hostname = "coedemo.dbenicio.com"

# Off for the baseline. Switch on from the command line during the demo:
#   tofu apply -var 'enable_waf=true'
enable_waf = false

# OWASP Core Ruleset tuning. See variables.tf.
owasp_paranoia_level  = 1
owasp_score_threshold = 40
owasp_action          = "block"

# Managed Rules — XSS Protection and LFI Protection (Cloudflare Managed Ruleset
# tags). The plan fails, suggesting the right tag, if a category name is wrong.
enable_xss_protection = true
enable_lfi_protection = true
xss_category          = "xss"
lfi_category          = "lfi"
managed_rules_action  = "block"
