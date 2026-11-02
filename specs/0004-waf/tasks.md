# 0004 — WAF — Tasks

| Field   | Value |
| ------- | ----- |
| Updated | 2026-10-29 |

> Draft breakdown — finalised once `spec.md` is `Approved`. A reference
> implementation already exists under
> [demos/wafdemo-owasp-juice-shop/](../../demos/wafdemo-owasp-juice-shop/); most
> tasks are about promoting it into a specified, template-rendered feature.

Each task references the requirement it satisfies. A task with no requirement
behind it is scope creep — either drop it or add the requirement to `spec.md`.

| # | Task | Covers | Status |
| - | ---- | ------ | ------ |
| 1 | Confirm account-level WAF on the tenant (Cloudflare Managed Ruleset), the zone's OWASP entitlement, and that the demo zone is Enterprise — on the account and the zone themselves. | FR-10 | todo |
| 2 | Generalise the reference WAF module into `src/terraform/_templates/feature/` so the wizard renders it, with the tenant-level ruleset kept to one root per account. | FR-1 | todo |
| 3 | Capture the baseline with the WAF off: SQLi authenticates; XSS and traversal reach the origin. | FR-2 | todo |
| 4 | Verify each vector is blocked (403 + Ray ID) with the WAF on and credited to the Cloudflare Managed Ruleset. | FR-3, FR-4, FR-7 | todo |
| 5 | Exercise the independent ruleset toggles and the evaluation order: managed ruleset disabled, OWASP takes over; enabled again, managed is credited. | FR-5, FR-6 | todo |
| 6 | Exercise action and sensitivity variables (action, score threshold, paranoia level). | FR-8, FR-9 | todo |
| 7 | Verify the plan-time guards: entitlement failures; proxied, origin-lock and zone-scope warnings. | FR-10, FR-12 | todo |
| 8 | Verify every off switch is an in-place disable — no ruleset destroyed or recreated, no DNS/origin change — and that no-bypass holds. | FR-13 | todo |
| 9 | Decide the tenant-level scope (every Enterprise zone, or a zone list) before the first apply, and remove or import any dashboard-created account entry point. | FR-4, FR-14 | todo |

## Definition of done

- [ ] Every acceptance criterion in `spec.md` passes.
- [ ] Code lives under `src/` and runs from a clean checkout.
- [ ] Component listed in its spec's row of `specs/README.md`.
- [ ] `specs/README.md` status updated.
- [ ] If AI usage is not `None`, `.gitignore` reviewed.
