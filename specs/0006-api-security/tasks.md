# 0006 — API security — Tasks

| Field   | Value |
| ------- | ----- |
| Updated | 2026-11-12 |

> Draft breakdown — finalised once `spec.md` is `Approved`. Builds on the WAF lab
> (`0004`) and the shared platform (`0001`); the mTLS task depends on settling the
> approach shared with the DDoS PoC.

Each task references the requirement it satisfies. A task with no requirement
behind it is scope creep — either drop it or add the requirement to `spec.md`.

The six demonstrations the RFP asks for map to tasks 3 (discovery and
inventory), 4 (schema validation), 5 (mTLS), 6a (API rate limiting), 6b (API WAF
policies) and 7 (malicious or anomalous traffic).

| # | Task | Covers | Status |
| - | ---- | ------ | ------ |
| 1 | Confirm Cloudflare API Shield is entitled on the demo zone. | FR-1 | done: Discovery and schema validation both ran on the zone, 8–10 Nov 2026 |
| 2 | Scaffold the `api-security` module behind `enable_api_security`, one sub-toggle per layer. | FR-1, FR-9 | todo |
| 3 | Enable endpoint discovery and retrieve the inventory after a traffic window. | FR-2 | done (PoC, dashboard): 21 new operations on 10 Nov 2026; the export is committed as a sample |
| 4 | Author an OpenAPI schema over the demonstrated endpoints and turn on schema validation. | FR-3 | done (PoC, dashboard): two schemas; 4/4 and 6/6 attacks blocked, 9–10 Nov 2026 |
| 5 | Settle the mTLS approach (reuse the DDoS PoC if it exposes a client-cert route) and require it on the API hostname/route. | FR-4 | **WIP**, owners Dinis and Micael: a first demo against the Juice Shop server, with curl presenting valid and invalid client certificates and detailed logs. Not yet written up in the testing plan |
| 6a | Add per-route rate limiting on API routes, independent of any zone-wide limit. | FR-5 | todo |
| 6b | Scope WAF policies to API routes, reusing `0004`. | FR-6 | todo |
| 7 | Enable anomaly/abuse detection and verify flagged events appear in the logs. | FR-7 | todo |
| 8 | Verify every rejection is attributable in the event log and each layer toggles independently with no origin/DNS change. | FR-8, FR-9 | in progress: Ray ID procedure written; the malformed-login blocks are not attributed yet |
| 9 | Document the discovery and schema validation measurements so they can be repeated, in [docs/api-security-testing-plan.md](../../docs/api-security-testing-plan.md). | FR-2, FR-3, FR-8 | done |

## Definition of done

- [ ] Every acceptance criterion in `spec.md` passes.
- [ ] Code lives under `src/` and runs from a clean checkout.
- [ ] Component listed in its spec's row of `specs/README.md`.
- [ ] `specs/README.md` status updated.
- [ ] If AI usage is not `None`, `.gitignore` reviewed.
