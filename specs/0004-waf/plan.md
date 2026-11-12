# 0004 — WAF — Plan

> Draft. `spec.md` is not yet `Approved`, so this covers **how** only in
> outline. A hand-written implementation already exists under
> [demos/wafdemo-owasp-juice-shop/](../../demos/wafdemo-owasp-juice-shop/) with
> its [runbook](../../docs/wafdemo-owasp-juice-shop.md); the plan below is about
> promoting that into a specified, template-rendered feature, and is filled in
> once the spec is approved. Builds on `0001`, which is delivered, for the
> origin lockdown that stops the edge being bypassed.

| Field   | Value |
| ------- | ----- |
| Status  | Draft |
| Updated | 2026-10-29 |

## Approach

One Terraform module, two rulesets in the `http_request_firewall_managed`
phase, both behind `enable_waf`:

- **Tenant level** — the account's entry point ruleset (`kind = "root"`)
  executes the **Cloudflare Managed Ruleset** whole, with a ruleset-wide
  override that enables every rule and sets the action to `block`. Its
  expression always ends in `cf.zone.plan eq "ENT"`, which Cloudflare requires
  for account-level managed rulesets, and can be narrowed to a list of zone
  names. Credited for the committed vectors.
- **Zone level** — the demo zone's entry point executes the **Cloudflare OWASP
  Core Ruleset** on the anomaly score, scoped to the demo hostname. Cloudflare
  evaluates it after the account level, so it only sees what the managed
  ruleset let through.

Every switch sets an execute rule's `enabled` flag; none deletes a ruleset. The
tag-based XSS and LFI protections of the first version are gone — see the note
at the top of [spec.md](spec.md).

The reference implementation is
[demos/wafdemo-owasp-juice-shop/terraform/cloudflare/waf/](../../demos/wafdemo-owasp-juice-shop/terraform/cloudflare/waf/);
promoting it means generalising it into `src/terraform/_templates/feature/` so
the wizard can render it like the other edge features. The tenant-level ruleset
does not belong to one demo, so promotion also has to decide where it lives —
see Risks.

## Alternatives considered

| Option | Why not |
| ------ | ------- |
| Managed Ruleset restricted to the `xss` and `lfi` tags (the first version) | No longer available; the only managed deployment that worked in the PoC was the whole Cloudflare Managed Ruleset. Recorded 2026-10-29. |
| Managed Ruleset on the demo zone | Ties the protection to one domain while the demo is moving domains. Tenant level by owner decision, 2026-10-29. |
| Delete the ruleset to switch off (`count = 0`) | A delete and re-create is slower, harder to reverse mid-demo, and loses the ruleset's ID and version history. Disabling the rule is an in-place update. |
| Dashboard-configured managed rules | Not reproducible from a clean checkout, and an account or zone holds one entry point per phase — mixing dashboard and Terraform fails. |
| Hand-written custom rules per attack | Re-implements what the managed and OWASP rulesets already do, and does not represent the product the RFP is about. |

## Components

| Component | Path | Responsibility |
| --------- | ---- | -------------- |
| WAF module | `demos/<name>/terraform/cloudflare/waf/` | Tenant-level Cloudflare Managed Ruleset and zone-level OWASP Core, behind `enable_waf`. Reference version already written. |
| Target app | `demos/<name>/` (Juice Shop) | The deliberately vulnerable origin the attacks land on. |

## Interfaces and data

- Inputs: `enable_waf`, `enable_cloudflare_managed_ruleset`,
  `enable_owasp_core_ruleset`, `managed_ruleset_zones`, `managed_rules_action`,
  `owasp_paranoia_level`, `owasp_score_threshold`, `owasp_action`, plus
  `zone_id` / `hostname`, and `account_id` (defaults to the zone's account).
- Cloudflare token: account-level WAF edit permission on the tenant, in
  addition to the zone permissions the runbook lists.
- Evidence per demo window: 403 + Ray ID at the client; matched ruleset/rule in
  Cloudflare Security Events, filtered by host.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Tenant-wide scope in a shared account | Every Enterprise zone in the tenant gets every managed rule blocking, including zones that are not part of the demo | Decide the scope before the first apply (spec open question). Narrow with `managed_ruleset_zones`; tell anyone sharing the tenant. |
| Every managed rule on, including those Cloudflare ships disabled | False positives on Juice Shop's own traffic during the demo | Rehearse normal browsing with the WAF on. `managed_rules_action = "log"` finds the culprit without blocking. |
| The account entry point is a singleton | A second demo, a colleague, or a dashboard deployment from the PoC already owns it; create fails with "a similar configuration already exists" | Import it, or delete the dashboard copy (see Rollout notes). Keep one Terraform root per tenant when promoting to a template. |
| Account or zone not entitled (account-level WAF is Enterprise; token scope) | WAF cannot be shown | Plan fails with the entitlement message; verify on the account and zone during `0001`. |
| A committed vector gets past the managed ruleset | Credited to OWASP instead, contradicting the spec | Security Events names the ruleset either way; record the real attribution in the testing plan at rehearsal. |
| Origin reachable directly | "Block" can be bypassed, demo collapses | Require `lock_origin_to_cloudflare`; the module warns when it is off. |

## Test and demo strategy

The demo is the test — run the committed vectors (testing plan 1.1–1.3) off then
on, capturing the baseline compromise and the block with its event-log entry.
Then disable the managed ruleset to show OWASP catching the same attacks, and,
with it still disabled, change the threshold to show sensitivity. Full cases in
[docs/waf-testing-plan.md](../../docs/waf-testing-plan.md).

## Rollout notes

Demo notes for the presenter. Standing the demo up from scratch is the
[runbook](../../docs/wafdemo-owasp-juice-shop.md); this section covers switching
the tenant-level Cloudflare Managed Ruleset during the demo.

**Disable and enable, never remove.** The Cloudflare Managed Ruleset stays
deployed in the tenant's entry point for the whole demo. Switching it only sets
its execute rule's `enabled` flag, so it comes back in seconds with the same ID
and configuration. `tofu destroy` is the only thing that removes it, and it is
not part of the demo.

From the WAF module, with `CLOUDFLARE_API_TOKEN` exported:

```bash
cd demos/wafdemo-owasp-juice-shop/terraform/cloudflare/waf
tofu init                                   # first time only

# Enable: WAF on. The managed ruleset defaults to on, OWASP too.
tofu apply -var 'enable_waf=true'

# Disable the managed ruleset only. It stays deployed; OWASP takes over.
tofu apply -var 'enable_waf=true' -var 'enable_cloudflare_managed_ruleset=false'

# Enable it again.
tofu apply -var 'enable_waf=true'

# Managed ruleset alone, OWASP disabled.
tofu apply -var 'enable_waf=true' -var 'enable_owasp_core_ruleset=false'
```

- **Read the plan before typing `yes`.** A switch is
  `~ update in-place` on `cloudflare_ruleset.tenant_managed`, with `enabled`
  changing, and ends in `0 to add, 1 to change, 0 to destroy`. Anything to
  destroy or replace means the variables do not match what is deployed. Stop
  and check them.
- **`-var` does not persist.** A bare `tofu apply` falls back to
  `terraform.tfvars`, where `enable_waf = false`, and disables both rules. To
  keep a state between applies, set the variables in `terraform.tfvars`.
- **Confirm on the API, not only in the plan.**
  `eval "$(tofu output -raw verify_command)"` prints one line per rule in
  evaluation order. The account line should read
  `accounts  true  efb7b8c949ac4650a09736fc376e9aee  Cloudflare Managed Ruleset, all rules, block`,
  and `false` once disabled.
- **OWASP only sees what the managed ruleset lets through.** For the
  sensitivity story (threshold, paranoia level), disable the managed ruleset
  first or nothing reaches OWASP.
- **Check the scope before the first apply.** With `managed_ruleset_zones = []`
  the ruleset covers every Enterprise zone in the account, not only the demo's.
  The demo zone itself must be Enterprise; the runbook's pre-flight call prints
  its plan.
- **If the plan or apply reports "exceeded maximum number of zone rulesets for
  phase"** or **"a similar configuration already exists"**, that zone or
  account already has a ruleset for the managed phase — the PoC's own zone
  ruleset, or one deployed from the dashboard. Removing a deployment in the
  dashboard can leave that ruleset behind, empty, so list the rulesets rather
  than asking for the entry point. Keep `success` and `errors` in the output:
  an empty result from a failed call looks the same as an empty account.

  ```bash
  SCOPE="zones/<zone-id>"          # or "accounts/<account-id>"
  curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/$SCOPE/rulesets" \
    | jq '{success, errors, leftovers: [.result[]? | select(.phase == "http_request_firewall_managed" and .kind != "managed") | {id, name, kind, last_updated}]}'
  ```

  Then delete the leftover, or import it so Terraform takes it over and
  replaces its rules with this module's:

  ```bash
  tofu import cloudflare_ruleset.zone_owasp     "zones/<zone-id>/<ruleset-id>"
  tofu import cloudflare_ruleset.tenant_managed "accounts/<account-id>/<ruleset-id>"
  ```
- **Rehearse normal browsing with the WAF on.** Every managed rule blocks,
  including rules Cloudflare ships disabled, so a false positive on the app's
  own traffic is possible. Find it before the audience does.
