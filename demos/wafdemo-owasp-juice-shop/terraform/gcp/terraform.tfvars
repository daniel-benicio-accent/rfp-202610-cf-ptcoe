# billing_account comes from TF_VAR_billing_account, not from this file.
project_id = "rfp-202610-wafdemo"
region     = "europe-west1"
zone       = "europe-west1-b"
app_name   = "wafdemo-owasp-juice-shop"
hostname   = "coedemo.dbenicio.com"
operator   = "user:daniel.benicio@opsylab.com.br"

# Only if the account belongs to an organization. One or the other, not both.
# org_id    = ""
# folder_id = ""

# On: 80 and 443 accept only Cloudflare's ranges, so the WAF cannot be
# bypassed by going to the VM's IP. Set false only to test the origin directly.
# See docs/wafdemo-owasp-juice-shop.md, step 3 ("close the side door").
lock_origin_to_cloudflare = true
