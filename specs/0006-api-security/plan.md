# 0006 — API security — Plan

> Draft. `spec.md` is not yet `Approved`; this covers **how** only in outline and
> is filled in after approval. Blocked on `0001` (proxied origin, lockdown) and
> leans on `0004` (WAF). Requires Cloudflare API Shield on the Enterprise tier.

| Field   | Value |
| ------- | ----- |
| Status  | Draft |
| Updated | 2026-10-29 |

## Approach

One Terraform module behind `enable_api_security`, adding the API Shield layers
as independently-toggleable sub-features: endpoint discovery, an OpenAPI schema
plus schema validation, mTLS on the API hostname/route, per-route rate limiting,
and anomaly detection. Each layer maps to an API Shield resource so the
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
| OpenAPI schema | `demos/<name>/` (or `src/`) | Schema over the demonstrated endpoints, loaded for validation. |
| Target API | `demos/<name>/` (Juice Shop) | The REST surface protected; shared with the WAF lab. |

## Interfaces and data

- Inputs: `enable_api_security` plus per-layer toggles (discovery, schema
  validation, mTLS, rate limiting, anomaly), the schema reference, and the
  mTLS trust configuration.
- Evidence per demo window: discovered-endpoint inventory; schema-violation,
  mTLS-refusal, rate-limit and anomaly events in Cloudflare logs.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| API Shield not active on the demo zone | The feature cannot be shown | Verify the entitlement on the zone before building, as with the WAF. |
| mTLS built twice (here and in the DDoS PoC) | Wasted effort | Share the DDoS PoC's mTLS setup; confirm it exposes a client-cert route to point at. |
| Overlap with `0002`/`0003`/`0004` blurs the demo | Audience cannot tell the features apart | Keep discovery, schema and mTLS as the `0006` story; reference the others for shared layers. |

## Test and demo strategy

The demo is the test — enable the layers one at a time and show each taking
effect: discovery populates the inventory, schema validation rejects an
off-schema request, mTLS refuses an unenrolled client, a per-route limit throttles
one route, anomaly detection flags abnormal use. Each rejection is read back from
the event log.

## Rollout notes

Blocked on `0001` and `0004`. Filled in once the spec is approved and the mTLS
approach (shared with the DDoS PoC) is settled.
