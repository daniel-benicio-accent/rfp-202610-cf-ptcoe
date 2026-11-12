# 0006 — API security — Plan

> Draft. `spec.md` is not yet `Approved`; this covers **how** only in outline and
> is filled in after approval. Builds on `0001` (proxied origin, lockdown), which
> is delivered, and leans on `0004` (WAF). Requires Cloudflare API Shield on the Enterprise tier.
> Discovery and schema validation have already run as a dashboard PoC
> (8–10 November 2026); see [Test and demo strategy](#test-and-demo-strategy).
> An mTLS demo is in progress with Dinis and Micael.

| Field   | Value |
| ------- | ----- |
| Status  | Draft |
| Updated | 2026-11-12 |

## Approach

One Terraform module behind `enable_api_security`, adding the six requested
capabilities as independently-toggleable sub-features: endpoint discovery, an
OpenAPI schema plus schema validation, WAF policies scoped to API routes, mTLS on
the API hostname/route, per-route rate limiting, and anomaly detection. Each layer maps to an API Shield resource so the
"progressive" story is literally switching layers on in order. WAF coverage for
API routes reuses `0004`; per-route rate limiting is the `0003` control scoped to
the API.

The demo target is the OWASP Juice Shop REST API already used by the WAF lab, so
the origin is shared rather than new.

## Alternatives considered

| Option | Why not |
| ------ | ------- |
| A custom API gateway / auth service at the origin | Moves the control off the edge and adds a component to run; the point is to show Cloudflare doing it. |
| Dashboard-only API Shield setup | Not reproducible from a clean checkout; the rest of the repo is Terraform-driven. |
| Auto-generating the OpenAPI schema from discovery | Useful later; for the demo a hand-authored schema over the shown endpoints is enough and more legible. |

## Components

| Component | Path | Responsibility |
| --------- | ---- | -------------- |
| API security module | `demos/<name>/terraform/cloudflare/api-security/` | API Shield layers behind `enable_api_security`, each sub-toggle a variable. |
| OpenAPI schemas | [demos/api-security-schemas-manifests/](../../demos/api-security-schemas-manifests/) | Hand-authored schemas over the demonstrated endpoints: five on Juice Shop, four on go-httpbin. Uploaded in the dashboard for the PoC. |
| Target APIs | Juice Shop, and a go-httpbin demo API | The REST surfaces under protection. Juice Shop is shared with the WAF lab. |
| Baseline traffic generator | [scripts/apidiscovery-juiceshop-baseline-traffic.py](../../scripts/apidiscovery-juiceshop-baseline-traffic.py) | Front-end-like, authenticated traffic over 45 Juice Shop operations, so Discovery has 2xx traffic to count. |
| Schema validation harness | [scripts/juiceshop_schema_validation_demo.sh](../../scripts/juiceshop_schema_validation_demo.sh) | Sends compliant and non-compliant requests and reports, with a Ray ID per case, whether the edge blocked each one. Uses its built-in cases, or derives cases from any OpenAPI JSON file. |

## Interfaces and data

- Inputs: `enable_api_security` plus per-layer toggles (discovery, schema
  validation, API WAF policies, mTLS, rate limiting, anomaly), the schema
  reference, and the mTLS trust configuration.
- Evidence per demo window: discovered-endpoint inventory; schema-violation,
  API WAF policy, mTLS-refusal, rate-limit and anomaly events in Cloudflare logs.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| API Shield not active on the demo zone | The feature cannot be shown | Verify the entitlement on the zone before building, as with the WAF. |
| mTLS built twice (here, in the DDoS PoC and in the RFP team's demo) | Wasted effort | Build on the demo in progress with Dinis and Micael, and check with them whether it is the DDoS PoC's setup before building anything new. |
| Overlap with `0002`/`0003`/`0004` blurs the demo | Audience cannot tell the features apart | The RFP asks for all six capabilities, so each gets its own demo. Reuse the other features' implementation, not their demos: target API routes, and name the control through the Ray ID. |
| Discovery is slow and sampled | The inventory is still empty on demo day | Start the generator at least three days ahead. On the PoC, new operations first appeared about 48 h after the traffic started. |
| A 403 at the edge gets credited to the wrong control | A slide claims schema validation for a block that came from another rule | Turn the WAF managed rulesets off for schema runs, and trace every 403 by its Ray ID. Three malformed-login cases are already blocked with no schema loaded. |
| The PoC configuration lives only in the dashboard | Not reproducible from a clean checkout (FR-1) | The testing plan records every dashboard step. Move the schema upload and the enforcement rule into the Terraform module (task 2). |

## Test and demo strategy

The demo is the test — enable the layers one at a time and show each taking
effect: discovery populates the inventory, schema validation rejects an
off-schema request, an API-scoped WAF policy blocks an attack on an API route,
mTLS refuses an unenrolled client, a per-route limit throttles one route, anomaly
detection flags abnormal use. Each rejection is read back from the event log.

Discovery and schema validation are written up as repeatable test cases in
[docs/api-security-testing-plan.md](../../docs/api-security-testing-plan.md):
prerequisites, the exact commands and parameters, the November 2026 run record
with Ray IDs, and how to trace a block to the control that fired.

## Rollout notes

Tips for the presenter, from the November 2026 PoC. The full procedure is in
the [testing plan](../../docs/api-security-testing-plan.md).

- **Start traffic three days ahead.** Discovery counts only 2xx responses at
  the edge, with at least 500 requests per operation in 10 days, and it is
  batch-processed. On the PoC, new operations first showed under
  **Web assets** > **Operations** > **Discovered** about 48 h after the
  generator started.
- **Run `--check` first.** The generator's preflight must report all 33 flows
  returning 2xx. If an edge rule blocks or challenges it, those operations are
  never discovered: on the PoC, a `PUT`/`DELETE` block on the host failed five
  flows until it was lifted.
- **Capture "without" before you upload.** Run the harness once before the
  schema goes on and keep its output. A schema can be deleted later to get
  back to "without"; its operations stay in the inventory.
- **Show one cause at a time.** Keep the WAF managed rulesets off during the
  schema runs, and look up each 403's Ray ID in Security Events before putting
  it on a slide. The malformed-login cases are blocked even without a schema,
  so do not present them as schema validation.
- **Mind the 31-day window.** Security Events keep events for 31 days.
  Export the event JSON for every Ray ID you plan to show.
- **mTLS route.** The go-httpbin partner cases need a client certificate. Set
  `SKIP_MTLS=on` to leave them out cleanly.

- **mTLS (WIP, Dinis and Micael).** The RFP team has a first demo against the
  Juice Shop server: curl presents a valid and then an invalid client
  certificate, and detailed logs show each outcome. Its tips go here once it is
  written up in the testing plan.

API-specific WAF policies, API rate limiting and anomalous-traffic protection
are still to do.
