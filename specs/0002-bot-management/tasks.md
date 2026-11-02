# 0002 — Bot management — Tasks

| Field   | Value |
| ------- | ----- |
| Updated | 2026-10-21 |

Blocked on `0001` delivering the proxied hostname and the origin lockdown. The
plan tier is settled (Enterprise with Bot Management), so the module shape is
known and these tasks are concrete.

| # | Task | Covers | Status |
| - | ---- | ------ | ------ |
| 1 | ~~Resolve the plan tier and pick the module shape~~ | FR-1, FR-6 | done — Enterprise, score-based rule, 2026-10-21 |
| 2 | Choose the bot score threshold and record the reasoning | FR-9 | todo |
| 3 | Capture the baseline: feature off, scripted client reaches origin | FR-2 | blocked on 0001 |
| 4 | Write the `bot-management` module behind `enable_bot_management`, with threshold and action as variables | FR-1, FR-6, FR-9 | blocked on 0001 |
| 4a | Add synthetic app endpoints and per-scenario counters without credential or form-data storage | FR-11 | implemented; runtime test pending |
| 4b | Add bounded containerized simulator for the six scenarios | FR-11 | implemented; unit tests pending |
| 5 | Verify the scripted client is refused and the origin counter stays flat | FR-3, FR-8 | blocked on 0001 |
| 6 | Verify a browser session is unaffected | FR-4 | blocked on 0001 |
| 7 | Verify a spoofed `Googlebot` user agent is still mitigated by the same rule | FR-5 | blocked on 0001 |
| 8 | Run bounded scenario samples and capture both counters | FR-8, FR-11 | blocked on 0001 |
| 9 | Capture the Cloudflare event log and the bot score distribution for the window | FR-7, FR-10 | blocked on 0001 |
| 10 | Show the match set changing when the threshold changes | FR-9 | blocked on 0001 |
| 11 | Write the presenter runbook for the sequence | — | blocked on 0001 |
| 12 | Document simulator container usage and safety limits | FR-11 | done |

## Definition of done

- [ ] Every acceptance criterion in `spec.md` passes.
- [ ] Code lives under `src/` and runs from a clean checkout.
- [ ] Component listed in its spec's row of `specs/README.md`.
- [ ] `specs/README.md` status updated.
- [ ] If AI usage is not `None`, `.gitignore` reviewed.

### Module-specific

- [ ] Phase set, and no other module claims the same phase on this zone.
- [ ] Match expression scoped to the demo hostname, not the whole zone.
- [ ] Baseline captured with the feature off, before anything else.
- [ ] Effect captured with it on, including what reached the origin.
- [ ] Cloudflare event log shows the matched rule and action.
