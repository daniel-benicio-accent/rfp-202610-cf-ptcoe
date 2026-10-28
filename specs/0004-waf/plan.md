# 0004 — WAF — Plan

> Draft. `spec.md` is not yet `Approved`, so this covers **how** only in
> outline. A hand-written implementation already exists under
> [demos/wafdemo-owasp-juice-shop/](../../demos/wafdemo-owasp-juice-shop/) with
> its [runbook](../../docs/wafdemo-owasp-juice-shop.md); the plan below is about
> promoting that into a specified, template-rendered feature, and is filled in
> once the spec is approved. Blocked on `0001` for the origin lockdown that
> stops the edge being bypassed.

| Field   | Value |
| ------- | ----- |
| Status  | Draft |
| Updated | 2026-10-28 |

## Approach

One Terraform module in the `http_request_firewall_managed` phase, scoped to the
demo hostname, behind `enable_waf`. It runs the Cloudflare Managed Ruleset with
every rule off except the `xss` and `lfi` tags (credited to XSS/LFI protection),
then the Cloudflare OWASP Core Ruleset on the anomaly score (credited to SQLi).
The reference implementation is
[demos/wafdemo-owasp-juice-shop/terraform/cloudflare/waf/](../../demos/wafdemo-owasp-juice-shop/terraform/cloudflare/waf/);
promoting it means generalising it into `src/terraform/_templates/feature/` so
the wizard can render it like the other edge features.

## Alternatives considered

| Option | Why not |
| ------ | ------- |
| Dashboard-configured managed rules | Not reproducible from a clean checkout, and a zone holds one managed ruleset per phase — mixing dashboard and Terraform fails. |
| Hand-written custom rules per attack | Re-implements what the managed and OWASP rulesets already do, and does not represent the product the RFP is about. |

## Components

| Component | Path | Responsibility |
| --------- | ---- | -------------- |
| WAF module | `demos/<name>/terraform/cloudflare/waf/` | Managed XSS/LFI + OWASP Core, behind `enable_waf`. Reference version already written. |
| Target app | `demos/<name>/` (Juice Shop) | The deliberately vulnerable origin the attacks land on. |

## Interfaces and data

- Inputs: `enable_waf`, `enable_xss_protection`, `enable_lfi_protection`,
  `managed_rules_action`, `owasp_paranoia_level`, `owasp_score_threshold`,
  `owasp_action`, plus `zone_id` / `hostname`.
- Evidence per demo window: 403 + Ray ID at the client; matched ruleset/rule in
  Cloudflare Security Events, filtered by host.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Managed-ruleset tag names drift between versions | A protection matches nothing | The module checks tags at plan time and lists the real ones — keep that guard. |
| Zone not entitled (Free plan / token scope) | WAF cannot be shown | Plan fails with the entitlement message; verify on the zone during `0001`. |
| Origin reachable directly | "Block" can be bypassed, demo collapses | Require `lock_origin_to_cloudflare`; the module warns when it is off. |

## Test and demo strategy

The demo is the test — run the committed vectors (testing plan 1.1–1.3) off then
on, capturing the baseline compromise and the block with its event-log entry.
Then switch XSS off to show OWASP catching it, and change the threshold to show
sensitivity. Full cases in [docs/waf-testing-plan.md](../../docs/waf-testing-plan.md).

## Rollout

Blocked on `0001` (proxied hostname and origin lockdown). Filled in once the spec
is approved.
