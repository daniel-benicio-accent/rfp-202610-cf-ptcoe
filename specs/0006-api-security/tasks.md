# 0006 — API security — Tasks

| Field   | Value |
| ------- | ----- |
| Updated | 2026-10-29 |

> Draft breakdown — finalised once `spec.md` is `Approved`. Builds on the WAF lab
> (`0004`) and the shared platform (`0001`); the mTLS task depends on settling the
> approach shared with the DDoS PoC.

Each task references the requirement it satisfies. A task with no requirement
behind it is scope creep — either drop it or add the requirement to `spec.md`.

| # | Task | Covers | Status |
| - | ---- | ------ | ------ |
| 1 | Confirm Cloudflare API Shield is entitled on the demo zone. | FR-1 | todo |
| 2 | Scaffold the `api-security` module behind `enable_api_security`, one sub-toggle per layer. | FR-1, FR-9 | todo |
| 3 | Enable endpoint discovery and retrieve the inventory after a traffic window. | FR-2 | todo |
| 4 | Author an OpenAPI schema over the demonstrated endpoints and turn on schema validation. | FR-3 | todo |
| 5 | Settle the mTLS approach (reuse the DDoS PoC if it exposes a client-cert route) and require it on the API hostname/route. | FR-4 | todo |
| 6 | Add per-route rate limiting and scope WAF policies to API routes (reusing `0004`). | FR-5, FR-6 | todo |
| 7 | Enable anomaly/abuse detection and verify flagged events appear in the logs. | FR-7 | todo |
| 8 | Verify every rejection is attributable in the event log and each layer toggles independently with no origin/DNS change. | FR-8, FR-9 | todo |

## Definition of done

- [ ] Every acceptance criterion in `spec.md` passes.
- [ ] Code lives under `src/` and runs from a clean checkout.
- [ ] Component listed in its spec's row of `specs/README.md`.
- [ ] `specs/README.md` status updated.
- [ ] If AI usage is not `None`, `.gitignore` reviewed.
