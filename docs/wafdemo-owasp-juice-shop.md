# WAF demo: OWASP Juice Shop behind Cloudflare

Runbook for [demos/wafdemo-owasp-juice-shop/](../demos/wafdemo-owasp-juice-shop/).
One small GCE VM runs [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/),
a deliberately vulnerable web app, in Podman. Cloudflare serves it on a public
hostname, and the WAF is switched on and off with one variable, so the demo can
show the same requests before and after.

```
visitor ──HTTPS──> Cloudflare edge ──HTTPS (full)──> VM :443  nginx ──> Juice Shop :3000
                   └ WAF: Cloudflare Managed (tenant), OWASP Core (zone)   (Podman, host network)
```

| Module | Path | What it creates |
| --- | --- | --- |
| Origin | `terraform/gcp/` | New project, VPC, firewall, static IP, Ubuntu 24.04 VM (e2-small), VM service account, IAP/OS Login access |
| Bootstrap | `bootstrap/startup-script.sh.tftpl` | Runs on every boot: upgrade (first boot), Podman, self-signed origin cert, nginx + Juice Shop containers |
| DNS | `terraform/cloudflare/zone/` | Proxied A record, per-hostname origin TLS mode |
| WAF | `terraform/cloudflare/waf/` | The Cloudflare Managed Ruleset at tenant (account) level, every rule blocking, and the Cloudflare OWASP Core Ruleset at zone level, both behind `enable_waf` |

This demo is written by hand, not rendered by `bootstrap-terraform.sh`, and
`project-nuke.sh` does not know about it. Tear it down with the steps at the end.

## Before you start

- OpenTofu and `gcloud`, set up as in [prerequisites.md](prerequisites.md),
  including `gcloud auth application-default login`.
- On the GCP side: permission to create projects (account with no organization,
  or `resourcemanager.projects.create` on the org/folder), and
  `roles/billing.user` on the billing account.
- On the Cloudflare side: the zone must already be active. Create a custom API
  token (My Profile → API Tokens → Create Token → Custom token) with:

  | Permission | Used by |
  | --- | --- |
  | Zone → Zone → Read | the pre-flight check below; `waf/` finds the tenant account from the zone |
  | Zone → DNS → Edit | `zone/` record; `waf/` proxied check |
  | Zone → Config Settings → Edit | `zone/` per-hostname SSL configuration rule |
  | Zone → Zone WAF → Edit | `waf/` OWASP ruleset and entitlement check |
  | Account → Account WAF → Edit | `waf/` tenant-level managed ruleset and entitlement check |

  Under Zone Resources, choose **Include → Specific zone → the demo zone**;
  under Account Resources, the tenant account. The Cloudflare Managed Ruleset
  runs at account level, which needs **Enterprise**, and only applies to
  Enterprise zones; the OWASP Core Ruleset runs on the zone and needs a **Pro
  plan or higher**. The WAF module checks both entitlements and refuses to plan
  without them.
- Check the values in each module's `terraform.tfvars`. The hostname is set in
  all three and must be the same everywhere.

```bash
cd demos/wafdemo-owasp-juice-shop/terraform
export TF_VAR_billing_account="XXXXXX-XXXXXX-XXXXXX"   # gcloud billing accounts list
export CLOUDFLARE_API_TOKEN="..."                      # needed from step 3
```

## 1. Deploy to GCP

```bash
cd gcp
tofu init
tofu plan -out=tfplan
tofu apply tfplan
tofu output
export DEMO_HOST="$(tofu output -raw hostname)"
```

The apply takes about three minutes, including a deliberate 60 s wait after the
APIs are enabled. The VM then bootstraps for another 3–6 minutes, and may reboot
once if the upgrade installed a new kernel. To follow it without SSH:

```bash
eval "$(tofu output -raw bootstrap_log_command)"
```

It is done when you see `[wafdemo-bootstrap] Juice Shop is up`. Check it directly:

```bash
curl -sI "$(tofu output -raw direct_url)" | head -1     # HTTP/1.1 200 OK
```

Open the `direct_url` in a browser to see the app. This works only while
`lock_origin_to_cloudflare = false`.

## 2. Connect to the VM

Port 22 is closed to the internet. SSH goes through Identity-Aware Proxy and
OS Login, so there are no keys to manage in metadata.

```bash
eval "$(tofu output -raw ssh_command)"
```

The first run generates `~/.ssh/google_compute_engine` and registers it with
OS Login. You can also use the **SSH** button on the VM in Console → Compute
Engine → VM instances, which goes through the same IAP route.

On the VM:

```bash
sudo podman ps                                       # juice-shop-app, juice-shop-proxy
sudo podman logs -f juice-shop-app
sudo journalctl -u google-startup-scripts.service    # bootstrap log
sudo google_metadata_script_runner startup           # re-run the bootstrap
```

## 3. Publish the hostname on Cloudflare

Put the VM's IP into `cloudflare/zone/terraform.tfvars` as `origin_ip`:

```bash
tofu output -raw public_ip        # still in gcp/
```

Check that the token can see the zone, and that `zone_id` in the tfvars is
the right one, before touching anything:

```bash
curl -s "https://api.cloudflare.com/client/v4/zones?name=${DEMO_HOST#*.}" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | jq '{success, errors, zones: [.result[] | {id, name, status, plan: .plan.name}]}'
```

Expect `success: true` and one zone. Its `id` must equal `zone_id` in
`cloudflare/zone/terraform.tfvars` and `cloudflare/waf/terraform.tfvars`, and
its `status` must be `active`. The `plan` value tells you in advance whether
step 4 will work: the tenant-level managed ruleset only covers Enterprise
zones.

Then:

```bash
cd ../cloudflare/zone
tofu init
tofu apply
```

This creates a **proxied** A record, so visitors resolve to Cloudflare and
never to the VM. It also adds a configuration rule that sets SSL to **Full**
for this hostname only, leaving the rest of the zone unchanged. Universal SSL
already covers a first-level subdomain, so HTTPS works straight away.

```bash
dig +short "$DEMO_HOST"                                  # Cloudflare IPs, not the VM's
curl -sI "https://$DEMO_HOST" | grep -iE '^HTTP|^server|^cf-ray'
```

Expect `200`, `server: cloudflare` and a `cf-ray` header.

**Then close the side door.** Until now the VM accepts anyone on 80/443, so the
WAF could be bypassed by going straight to the IP. In `gcp/terraform.tfvars` set
`lock_origin_to_cloudflare = true`, then:

```bash
cd ../../gcp && tofu apply
curl -sI --max-time 5 "$(tofu output -raw direct_url)"   # now times out
curl -sI "https://$DEMO_HOST" | head -1                   # still 200 through Cloudflare
```

> **Dashboard alternative:** DNS → Records → Add record: type `A`, the
> subdomain as name, the VM IP, Proxy status **Proxied**, TTL Auto. Then Rules →
> Configuration Rules → hostname equals the demo hostname → SSL **Full**. Use
> either the dashboard or Terraform for a record, not both: Terraform fails if
> the record already exists.

## 4. Put the WAF in front, and take it away again

The hostname stays proxied the whole time. Only the inspection changes.

**Baseline (WAF off).** This is the state after step 3. Run the requests you plan
to show and note that they reach the app.

**Switch the WAF on:**

```bash
cd ../cloudflare/waf
tofu init
tofu apply -var 'enable_waf=true'
```

This deploys two rulesets. They run in this order:

| # | Level | What Cloudflare runs | Scope | Blocks when |
| - | --- | --- | --- | --- |
| 1 | Tenant (account) | Cloudflare Managed Ruleset, every rule on, action `block` | Enterprise zones in the account, optionally only `managed_ruleset_zones` | any one rule matches |
| 2 | Zone | Cloudflare OWASP Core Ruleset, PL1 | the demo hostname | the anomaly score reaches 40 (rule *949110*) |

Cloudflare evaluates account-level rulesets before zone-level ones, and a block
ends evaluation, so the managed ruleset is credited first and OWASP inspects
only what it let through. The change is live within seconds.

> The first version of this module ran the managed ruleset restricted to its
> `xss` and `lfi` tags, as "Managed Rules — XSS Protection" and "LFI
> Protection". Those are no longer available; the whole Cloudflare Managed
> Ruleset was the only managed deployment that worked. See the note in
> [spec 0004](../specs/0004-waf/spec.md).

Before anything is created, the plan checks:

| Check | If it fails |
| --- | --- |
| The account is entitled to the Cloudflare Managed Ruleset at account level | The plan **stops**: not Enterprise, or a token without Account WAF permission. |
| The zone is entitled to the OWASP Core Ruleset | The plan **stops**: Free plan, or a token without Zone WAF permission. |
| The demo zone is in `managed_ruleset_zones`, when that list is set | **Warning**: the managed ruleset never inspects the demo. |
| The hostname is a proxied record | **Warning**: the traffic never reaches Cloudflare, so the WAF never sees it. |
| The origin is locked to Cloudflare | **Warning**: the WAF can be skipped by going straight to the VM's IP. |

Fix any warning before the demo. Then confirm what is deployed, with the rules
in the order Cloudflare evaluates them:

```bash
tofu output cloudflare_managed_ruleset
eval "$(tofu output -raw verify_command)"
# accounts  true    efb7b8c949ac4650a09736fc376e9aee    Cloudflare Managed Ruleset, all rules, block
# zones     true    4814384a9e5d4991b9815dcfc25d2f1f    Cloudflare OWASP Core Ruleset, PL1, threshold 40, block
```

Repeat the baseline requests. The ones the rules catch now get Cloudflare's
block page (403, with a Ray ID) and never reach the VM. In the dashboard,
Security → Events, filtered by host, shows which ruleset and which rule fired:
**Cloudflare Managed Ruleset** with the matching rule's name, or **Cloudflare
OWASP Core Ruleset** with the anomaly score reached.

Disable the managed ruleset, to show OWASP catching what it would have caught,
then enable it again. Neither removes anything; the plan is an in-place update
of the rule's `enabled` flag. The full set of commands and checks is in the
Rollout notes of [the 0004 plan](../specs/0004-waf/plan.md#rollout-notes).

```bash
tofu apply -var 'enable_waf=true' -var 'enable_cloudflare_managed_ruleset=false'
tofu apply -var 'enable_waf=true'
```

Tuning, for showing sensitivity against false positives. Disable the managed
ruleset first, or nothing reaches OWASP. If a request gets past OWASP, it
scored below the threshold:

```bash
tofu apply -var 'enable_waf=true' -var 'enable_cloudflare_managed_ruleset=false' -var 'owasp_score_threshold=25'   # high sensitivity
tofu apply -var 'enable_waf=true' -var 'enable_cloudflare_managed_ruleset=false' -var 'owasp_paranoia_level=2'     # more rules
tofu apply -var 'enable_waf=true' -var 'owasp_action=managed_challenge'            # challenge, not block
tofu apply -var 'enable_waf=true' -var 'managed_rules_action=managed_challenge'    # same, for the managed ruleset
```

**Switch the WAF off:**

```bash
tofu apply -var 'enable_waf=false'
```

This disables both rules in place; the rulesets stay deployed. Requests reach
Juice Shop again, still through Cloudflare. Only `tofu destroy` removes the
rulesets.

**Take Cloudflare out of the path entirely.** This is optional and a different
point. It shows the app with no edge at all, not just with no WAF.

```bash
cd ../../gcp  && tofu apply -var 'lock_origin_to_cloudflare=false'
cd ../cloudflare/zone && tofu apply -var 'proxied=false'
```

DNS now returns the VM's own IP. HTTPS hits the self-signed origin certificate,
so the browser warns. Revert both before going back to the WAF story.

> **Dashboard alternative:** in the account's WAF managed rules, deploy the
> Cloudflare Managed Ruleset to Enterprise zones, with every rule enabled and the
> ruleset action set to Block. On the demo zone, Security → WAF → Managed rules,
> deploy the Cloudflare OWASP Core Ruleset scoped to the demo hostname, and set
> paranoia level, score threshold and action. Do not mix with the Terraform
> module: an account and a zone each hold one managed-WAF entry point, and
> whichever was created second fails.

## Tear down

The order is the reverse of creation:

```bash
cd demos/wafdemo-owasp-juice-shop/terraform
tofu -chdir=cloudflare/waf  destroy
tofu -chdir=cloudflare/zone destroy
tofu -chdir=gcp             destroy
```

The first step also removes the tenant-level managed ruleset from the account,
for every zone it covered.

The last step deletes the project. GCP keeps it in a pending-deletion state for
30 days, and the project ID cannot be reused during that time. Choose a new
`project_id` before deploying again.

Left running, the demo costs on the order of US$15–20 a month: an e2-small VM,
an in-use static IP and a 10 GB disk.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Project creation fails on billing | Missing `roles/billing.user` on the billing account, or wrong `TF_VAR_billing_account`. |
| Project creation fails on parent | The account belongs to an organization: set `org_id` or `folder_id` in `gcp/terraform.tfvars`. An org policy blocking external IPs (`constraints/compute.vmExternalIpAccess`) also stops the VM. |
| `direct_url` gives 502 | Juice Shop is still starting. Wait for the bootstrap log line, or check `sudo podman logs juice-shop-app`. |
| IAP SSH: `failed to connect to backend` | The VM is still booting or rebooting, or the IAP firewall rule is missing. Wait a minute and retry. |
| SSH: `Permission denied (publickey)` | OS Login roles still propagating, or `operator` is not the account `gcloud` is logged in as. |
| `403 Forbidden` … `"code":10000,"message":"Authentication error"` on every Cloudflare call | The token cannot act on this zone. It may be scoped to another zone or account, it may lack the permissions above, or `zone_id` may be wrong. Run the pre-flight check in step 3. If DNS and rulesets both fail, the problem is zone scope, not a single missing permission. |
| Cloudflare 521 / 522 | Origin unreachable: VM down, containers not running, or the firewall lock is on with a stale range list — re-apply `gcp/`. |
| Cloudflare 525 / 526 | TLS mode mismatch. Use `origin_ssl_mode = "full"`; `strict` rejects the self-signed certificate. |
| `a similar configuration already exists`, or `exceeded maximum number of zone rulesets for phase` | That account or zone phase already has an entry point, created in the dashboard, by an earlier version of this module, or by another demo. Delete it there, or import it into this module — see the Rollout notes in [the 0004 plan](../specs/0004-waf/plan.md#rollout-notes). |
| WAF plan: `403` with code `9109` on `data.cloudflare_zone.demo`, or `10000` on `dns_records` | The token lacks **Zone → Zone → Read** or **Zone → DNS**. Account-level permissions with the same names (e.g. Account → DNS Settings) do not cover them. |
| WAF plan: `Account … has no access to the Cloudflare Managed Ruleset` | The account is not Enterprise with account-level WAF, or the token lacks Account WAF permission on it. |
| WAF plan: `Zone … has no access to the Cloudflare OWASP Core Ruleset` | The zone is on the Free plan, or the token lacks Zone WAF permission. OWASP needs Pro or higher. |
| WAF on, but nothing credited to the Cloudflare Managed Ruleset | The demo zone is not Enterprise, or not in `managed_ruleset_zones`. Account-level managed rulesets skip it. |
| WAF plan warns `not a proxied record` or `origin VM still accepts traffic` | See the checks table in step 4. Both mean requests can avoid the WAF. |
| Record conflicts with the bot demo | `demos/cfdemo-capability-bot/terraform/cloudflare/zone` uses the same hostname. Apply only one of the two. |
