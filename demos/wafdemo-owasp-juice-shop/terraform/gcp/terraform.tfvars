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

# Flip to true once Cloudflare is serving the hostname. See
# docs/wafdemo-owasp-juice-shop.md, step 4.
lock_origin_to_cloudflare = false
