# 0006 — API security

| Field     | Value |
| --------- | ----- |
| Status    | Draft |
| Owner     | d.de.freitas.alves |
| Created   | 2026-10-29 |
| Updated   | 2026-10-29 |
| AI usage  | Vendor-side only. Cloudflare API Shield uses machine learning at the edge to discover API endpoints and to flag anomalous API traffic. We configure and consume the outcome; we do not train or host a model, and nothing AI-related is generated into the working tree — so no new `.gitignore` entries are needed beyond the existing assistant-tooling block. See [docs/conventions.md](../../docs/conventions.md). |

## Summary

Show that Cloudflare protects an API as an API — not just as web traffic —
by discovering its endpoints, enforcing a schema, authenticating callers,
rate-limiting per route and flagging anomalous use, in front of the demo
application's REST API.

## Context

The RFP update of 29 October 2026 introduces **progressive API protection** as a
required capability. "Progressive" because it is delivered and demonstrated in
layers, each independently switchable: discovery first (you cannot protect what
you cannot see), then a schema and per-route policy, then authentication and
anomaly detection on top.

There is a clear path on top of the existing WAF lab. The WAF demo already runs
against [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/), whose
`/rest` and `/api` surface is a real REST API with a published companion guide
("Pwning OWASP Juice Shop"). The Juice Shop CTF scoreboard (CTFd) exposes its
own documented REST API as well. Either gives a concrete, non-trivial API to put
Cloudflare API Shield in front of, so the capability is shown against a real
surface rather than a toy endpoint.

This feature overlaps deliberately with others and reuses them rather than
restating them: API-specific **WAF** policies build on `0004`; API **rate
limiting** is the rate-based control that `0003` otherwise covered, scoped to API
routes; **bot** defence of APIs is `0002`. What is unique to `0006` is treating
the API as a declared contract — discovery, schema validation and mTLS.

Depends on `0001` for the proxied origin and lockdown, and leans on `0004` for
the WAF layer. Requires Cloudflare **API Shield**, available on our Enterprise
tier.

## Goals

- The API's endpoints are discovered and inventoried, so the protected surface
  is known rather than assumed.
- Requests that do not match the API's schema are rejected at the edge.
- The API can require a client certificate (mTLS), so only enrolled callers
  reach it.
- Rate limits are expressed per API route, not just per zone.
- Malicious or anomalous API traffic is flagged and can be mitigated.
- Each layer is switchable on its own, so the "progressive" story is literal:
  the audience sees protection added one layer at a time.
- Every control is expressed as code, reviewable and toggleable.

## Non-goals

- Securing the application's own code. The target is deliberately vulnerable
  (Juice Shop); this is about the edge in front of the API, not fixing the API.
- Full GraphQL protection. The demo surface is REST; GraphQL is a later story.
- Authoring a production OpenAPI schema for a third-party app. A schema covering
  the demonstrated endpoints is enough to show validation.
- General web-app WAF coverage — that is `0004`. Here the WAF policies are the
  subset scoped to API routes.
- A bespoke API gateway or custom auth service. Authentication is the edge's
  (mTLS / API tokens), not a new component.

## Scenarios

**S-1 — The API surface is discovered**

- **Given** the hostname is proxied and API Shield is enabled
- **When** real traffic flows to the API for a window
- **Then** Cloudflare lists the discovered endpoints, and the inventory can be
  reviewed and labelled — the protected surface is explicit

**S-2 — Off-schema requests are rejected**

- **Given** a schema describing the API's endpoints is loaded and validation is on
- **When** a request arrives with a body, parameter or method the schema does
  not allow
- **Then** it is rejected at the edge before reaching the origin, with the
  violation visible in the logs

**S-3 — Only enrolled clients reach the API (mTLS)**

- **Given** mTLS is required on the API hostname or route
- **When** a client presents no certificate, or an untrusted one
- **Then** the connection is refused at the edge; a client with an enrolled
  certificate is allowed through

**S-4 — Per-route rate limiting**

- **Given** a rate limit is set on a specific API route
- **When** a caller exceeds the limit on that route
- **Then** it is throttled or challenged, while other routes are unaffected

**S-5 — Anomalous API use is flagged**

- **Given** API Shield abuse/anomaly detection is enabled
- **When** a caller drives an abnormal volume or sequence against the API
- **Then** Cloudflare flags it, and the event is visible for the demo window

## Functional requirements

| ID | Requirement | Scenario |
| ---- | ----------- | -------- |
| FR-1 | API security is defined in Terraform behind an `enable_api_security` toggle, with each layer (discovery, schema validation, mTLS, rate limiting, anomaly) independently switchable. | S-1–S-5 |
| FR-2 | API endpoint discovery is enabled and the discovered inventory is retrievable for review. | S-1 |
| FR-3 | A schema (OpenAPI) covering the demonstrated endpoints is loaded, and schema validation rejects non-conforming requests at the edge. | S-2 |
| FR-4 | The API hostname or route can require mTLS; requests without a valid enrolled client certificate are refused. | S-3 |
| FR-5 | Rate limiting can be expressed per API route, independently of any zone-wide limit. | S-4 |
| FR-6 | WAF policies can be scoped specifically to API routes, reusing `0004` rather than duplicating it. | S-2, S-5 |
| FR-7 | Anomalous / malicious API traffic is detected and surfaced in Cloudflare's logs for the demo window. | S-5 |
| FR-8 | Every rejection (schema, mTLS, rate limit, anomaly) is attributable in Cloudflare's event log with the control that fired. | S-2–S-5 |
| FR-9 | Each layer can be enabled or disabled live, without an origin or DNS change, so the progressive story is shown in order. | S-1–S-5 |

## Non-functional requirements

| ID    | Requirement | Target |
| ----- | ----------- | ------ |
| NFR-1 | Enable/disable a layer during a live demo | Under 60 seconds, no environment rebuild |
| NFR-2 | A rejection is self-explaining | Log entry names the control (schema / mTLS / rate limit / anomaly) and the request |
| NFR-3 | Repeatability | The full layered sequence runs twice in a row with the same result |
| NFR-4 | Tier dependency | Implementable on our Enterprise tier with API Shield; verified on the demo zone before rehearsal |

## Acceptance criteria

- [ ] Discovery on: the API's endpoints appear in the inventory after a traffic window.
- [ ] Schema validation on: a non-conforming request is rejected at the edge and logged; a conforming one passes.
- [ ] mTLS on: a request with no/invalid client certificate is refused; an enrolled one is allowed.
- [ ] A per-route rate limit throttles that route while others are unaffected.
- [ ] An anomalous-traffic pattern is flagged and visible in the logs.
- [ ] Each layer toggles independently with no origin/DNS change in the plan.
- [ ] Every rejection names the control that fired in the event log.

## Open questions

| Question | Owner | Resolution |
| -------- | ----- | ---------- |
| Which API is the demo target — the Juice Shop `/rest` + `/api` surface, the CTFd scoreboard API, or both? | d.de.freitas.alves | Leaning Juice Shop (reuses the WAF lab origin), with the CTFd API as a second, independently-documented surface if time allows. |
| How is mTLS demonstrated, and can it reuse the DDoS PoC? The owner has an in-progress DDoS PoC intended to carry mTLS support, to avoid building it twice. | d.de.freitas.alves | Prefer sharing the DDoS PoC's mTLS setup. Confirm the PoC exposes a client-cert-protected route this spec can point at; otherwise stand up mTLS on the API hostname directly. |
| Where does the OpenAPI schema come from? Juice Shop does not publish one covering the whole surface. | | A hand-authored schema over the demonstrated endpoints is enough for the validation story; decide how many endpoints to cover. |
| Does the move to the target **Azure EBC** environment affect API Shield setup? | d.de.freitas.alves | API Shield is edge-side and origin-agnostic; confirm once the EBC environment and zone are decided. |
| How much overlaps with `0002` (bot) and `0003` (rate limiting), and how do we keep each demo legible? | | Keep discovery, schema and mTLS as the `0006`-unique story; reference `0002`/`0003`/`0004` for the shared layers rather than re-demoing them. |
