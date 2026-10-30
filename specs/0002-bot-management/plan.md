# 0002 — Bot management — Plan

> Draft. `spec.md` is not yet `Approved`, and this cannot be built until `0001`
> delivers a proxied hostname and the origin lockdown. The plan-tier question
> that previously blocked the design is resolved: Enterprise with the Bot
> Management add-on.

| Field   | Value |
| ------- | ----- |
| Status  | Draft |
| Updated | 2026-10-21 |

## Approach

A custom rule in the `http_request_firewall_custom` phase matching on
`cf.bot_management.score` below a configurable threshold, with the action taken
from a variable so FR-6 is a value change rather than a rewrite. Verified bots
are excluded from the match so the rule expresses "automated and not a crawler
we trust" rather than "automated".

A separate bounded CLI container exercises six synthetic scenarios against
the app's login, catalogue and form routes without sending credentials or form
data.

Matching on score rather than user agent is the point of the feature, not an
implementation detail — it is what makes S-3 work. A spoofed `Googlebot` scores
as automated because Cloudflare verifies crawlers by network identity, so the
same rule that catches plain `curl` catches the spoof, with no extra
configuration. The demo should show that as one rule, not two.

## Alternatives considered

| Option | Why not |
| ------ | ------- |
| Super Bot Fight Mode | Available on lower tiers, with fixed categories instead of a score. Now moot — Enterprise gives the score, which is both a better demo and a better representation of the product. |
| Hand-written WAF rules on user agent | Exactly the anti-pattern the demo should refute. Useful only as a deliberate contrast, if we want to show the naive approach failing first. |
| Turnstile on the app | Protects a form, not the API surface, and moves the control off the edge. Different story. |

## Components

| Component | Path | Responsibility |
| --------- | ---- | -------------- |
| Bot module | `demos/<name>/terraform/cloudflare/bot-management/` | The score-based rule, behind `enable_bot_management`. Threshold and action are variables. Rendered from `src/terraform/_templates/feature/`. |
| Bot simulator | `src/load-generator/` | One-shot container CLI for six named scenarios; at most ten sequential requests per run. |
| Origin counter | `src/app/` | Arrival count for FR-8. Delivered by `0001` task 10. |

## Interfaces and data

- Rule inputs: `bot_score_threshold` (default 30), `mitigation_action`
  (`block` | `managed_challenge` | `js_challenge`), `enable_bot_management`.
- Evidence per demo window: requests sent (load generator), requests arrived
  (origin counter), mitigated requests and matched rule (Cloudflare event log),
  score distribution (bot analytics).
- Simulator inputs: one scenario and a configured HTTPS hostname; no arbitrary
  URL, credentials, form content, concurrency or redirects.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Add-on active on the account but not the demo zone | The flagship feature fails at rehearsal | Verify on the zone itself — `0001` task 2 — before building anything here. |
| Managed challenge renders as a browser page, so `curl` sees HTML rather than a clean refusal | Terminal evidence reads as ambiguous | Use `block` for the terminal sequence; show `managed_challenge` in the browser. Both are available from the same variable. |
| Threshold chosen without thought invites a false-positive question we cannot answer | Credibility in the room | Pick the threshold deliberately and be ready to show the score distribution behind it. |
| Cloudflare provider v5 restructured the ruleset resources | Lost time on resource naming | Pin the provider and work from the v5 docs, not v4 examples. |
| Bot score is mistaken for rate limiting or account security | Repeated login attempts or account takeover remain possible | Use spec `0003` for rate limits and identity controls such as MFA for real accounts. |

## Test and demo strategy

The demo is the test. Run S-1 with the feature off, then on, capturing the
origin counter both times; S-2 in a browser; S-3 as a single `curl -A Googlebot`;
S-4 from the load generator. Capture the event log and the score distribution
for the window. Then change the threshold and show the match set change — that
is the FR-9 evidence.

## Rollout

Blocked on `0001`. Needs the proxied hostname (FR-5) and the origin lockdown
(FR-7) before any of this can be shown honestly — without them, a "blocked"
request can simply be retried against the Cloud Run URL.
