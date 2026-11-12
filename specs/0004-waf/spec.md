# 0004 — WAF

| Field     | Value |
| --------- | ----- |
| Status    | Draft |
| Owner     | d.de.freitas.alves |
| Created   | 2026-10-28 |
| Updated   | 2026-10-29 |
| AI usage  | None. The WAF is signature- and anomaly-scored rule matching (Cloudflare Managed Ruleset and OWASP Core Ruleset); no model is trained, hosted or invoked, and nothing AI-related is generated into the working tree. No `.gitignore` change is required. See [docs/conventions.md](../../docs/conventions.md). |

> **Note — PoC finding, 29 October 2026.** "Managed Rules — XSS Protection" and
> "Managed Rules — LFI Protection" are **no longer available** and have been
> removed from this spec and from the Terraform. The PoC built them as the
> Cloudflare Managed Ruleset restricted to its `xss` and `lfi` rule tags; of the
> managed deployments tried, **the only one that worked was the Cloudflare
> Managed Ruleset itself.** It is therefore deployed whole, with **every rule
> enabled and set to `block`**, and at the **tenant level** (the Cloudflare
> account) rather than on the demo domain. XSS and path traversal are now
> credited to the Cloudflare Managed Ruleset, not to separate protections. The
> requirements removed with this change are struck through below rather than
> renumbered.

## Summary

Show that the Cloudflare WAF recognises a class of application-layer attacks and
refuses them at the edge, before they reach the origin — the same request
accepted with the WAF off and refused with it on, with the matched ruleset named
in Cloudflare's event log.

## Context

The RFP asks for protection against the OWASP Top 10. The most convincing way to
answer is not a slide but a terminal: a request that genuinely compromises the
application when nothing is in front of it, and is stopped with a reason when the
WAF is switched on.

The demo already exists in hand-written form — [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/),
a deliberately vulnerable app, on a GCE VM behind Cloudflare, with the WAF driven
by a single `enable_waf` variable. Its runbook is
[docs/wafdemo-owasp-juice-shop.md](../../docs/wafdemo-owasp-juice-shop.md) and
the attacks are scripted in the `pt-cybersecurity-coe` Bruno collection. This
spec captures what that demo must prove so the capability is specified rather
than only built, and so it can be reproduced from a clean checkout.

The full test surface is the OWASP Top 10:2025 catalogue in
[docs/waf-testing-plan.md](../../docs/waf-testing-plan.md). Of it, three vectors
are committed for this demo — **SQL injection (1.1)**, **reflected XSS (1.2)**
and **path/directory traversal (1.3)** — because they cover the requirement in
the solution deck. All three are expected to be caught by the **Cloudflare
Managed Ruleset**, which runs first; the **Cloudflare OWASP Core Ruleset** is
the second layer, and takes over when the managed ruleset is switched off. The
remaining cases were deprioritised at the 26 October 2026 scope meeting; see
Non-goals.

The managed ruleset lives at the tenant level so that it is not tied to one
domain. The demo currently runs on a personal lab domain and is moving to the
target tenant and domain (see `0001`); a protection defined on the account
carries over to any Enterprise zone in it, where one defined on the zone would
have to be rebuilt.

Builds on `0001`, which is delivered. A WAF demo is only honest if the origin cannot be reached
directly — otherwise a "blocked" request is simply retried against the VM's IP
and the whole point collapses. The platform's origin lockdown
(`lock_origin_to_cloudflare`) is therefore a precondition, not a detail, and the
WAF module warns at plan time when it is missing.

## Goals

- A real attack (SQLi) compromises the app with the WAF off, and is blocked at
  the edge with it on — the before/after is unambiguous.
- Each committed vector is credited to a named Cloudflare control in the event
  log: the Cloudflare Managed Ruleset first, the OWASP Core Ruleset when the
  managed ruleset is off.
- A block is visible and attributable: 403 at the client, and the matched
  ruleset and rule in Cloudflare's event log.
- The WAF is expressed as code, switched with one variable, with no origin or
  DNS change between baseline and protected.
- The Cloudflare Managed Ruleset is defined at the tenant level, not on the demo
  domain, with every rule enabled and blocking.
- Each ruleset can be disabled and re-enabled independently, without being
  removed, so the demo can show the OWASP ruleset catching an attack the
  managed ruleset would otherwise have taken first.
- Sensitivity is adjustable (OWASP score threshold, paranoia level) to tell the
  false-positive story on demand.

## Non-goals

- **The deprioritised OWASP Top 10:2025 cases (tests 1.4–1.12).** Out of
  committed scope as of 26 October 2026, and documented in the testing plan for
  the delivery team. Several also belong to other features — rate limiting
  (`0003`) and bot management (`0002`) — not the WAF.
- **Rate-based and brute-force mitigation.** That is `0003`; keeping it separate
  is what makes each feature legible on its own.
- **Tuning the ruleset for a production traffic profile.** Every managed rule
  is on and blocking by decision; false-positive tuning is shown as a
  capability, not delivered as a hardened configuration.
- **Selecting managed rules by tag** (the former XSS and LFI protections). See
  the note at the top.
- **Protecting a bespoke origin application.** The target is Juice Shop, chosen
  because it is vulnerable on purpose; this spec does not cover securing the
  platform's own Flask app.
- **Running the Cloudflare WAF alongside dashboard-created managed rules in the
  same account or zone phase.** Each entry point is managed from one place —
  Terraform.

## Scenarios

Written from the presenter's and audience's point of view.

**S-1 — SQL injection is blocked at the edge**

- **Given** the hostname is proxied by Cloudflare and the WAF is off
- **When** the login endpoint receives `' OR 1=1 --` as the email
- **Then** the app authenticates the request as `admin` and returns a token —
  the baseline shows a real compromise
- **And when** the WAF is enabled and the same request is repeated
- **Then** Cloudflare returns a 403 block page with a Ray ID, the origin never
  sees the request, and the Cloudflare Managed Ruleset is named in the event log

**S-2 — Cross-site scripting is blocked**

- **Given** the WAF is off
- **When** the product search receives `q=<script>alert(1)</script>`
- **Then** the request reaches the origin (baseline)
- **And when** the WAF is enabled and the request is repeated
- **Then** it is blocked (403) and credited to the Cloudflare Managed Ruleset

**S-3 — Path traversal is blocked**

- **Given** the WAF is off
- **When** the file endpoint receives an encoded `../../../../etc/passwd`
- **Then** the request reaches the origin (baseline)
- **And when** the WAF is enabled and the request is repeated
- **Then** it is blocked (403) and credited to the Cloudflare Managed Ruleset

**S-4 — Switching a ruleset off and on, live**

- **Given** the WAF is enabled with the Cloudflare Managed Ruleset and the OWASP
  Core Ruleset both on
- **When** the managed ruleset is disabled and the attacks are repeated
- **Then** they are now caught by the OWASP Core Ruleset instead, showing
  defence in depth rather than a single rule
- **And when** the managed ruleset is enabled again
- **Then** it is credited again, and at no point was a ruleset removed or
  recreated

**S-5 — The WAF cannot be bypassed**

- **Given** the WAF is enabled
- **When** a request goes straight to the origin VM's IP rather than the hostname
- **Then** it fails (the origin is locked to Cloudflare), so there is no path
  around the edge

**S-6 — Sensitivity is tunable**

- **Given** the WAF is enabled and the managed ruleset is disabled, so the OWASP
  Core Ruleset is the one inspecting
- **When** the OWASP score threshold or paranoia level is changed
- **Then** the set of requests the ruleset acts on changes accordingly, which is
  the handle for the false-positive conversation

**S-7 — The managed ruleset belongs to the tenant, not to a domain**

- **Given** the Cloudflare Managed Ruleset is deployed at the tenant level
- **When** the demo is served from another Enterprise zone in the same account
- **Then** that zone is protected without the managed ruleset being redeployed
  or rewritten

## Functional requirements

| ID | Requirement | Scenario |
| ---- | ----------- | -------- |
| FR-1 | The WAF is a Terraform module behind a single `enable_waf` variable; off by default so the baseline is shown first. | S-1 |
| FR-2 | With the WAF off, each committed attack reaches the origin, and the SQLi attack genuinely authenticates — the baseline is a real compromise, reproducibly. | S-1, S-2, S-3 |
| FR-3 | With the WAF on, each committed attack is blocked at the edge (403 with a Ray ID) and never reaches the origin. | S-1, S-2, S-3 |
| FR-4 | The Cloudflare Managed Ruleset is deployed at the tenant level (the Cloudflare account's entry point), not on the demo zone, with every rule enabled and the action `block`; it is credited for the committed vectors. The Cloudflare OWASP Core Ruleset runs at zone level, scoped to the demo hostname, as the second layer on its anomaly score. | S-1, S-2, S-3, S-7 |
| FR-5 | The managed ruleset and the OWASP ruleset are each independently toggleable (`enable_cloudflare_managed_ruleset`, `enable_owasp_core_ruleset`) without restructuring the module. | S-4 |
| FR-6 | Rule evaluation order is defined and deliberate: the tenant-level managed ruleset runs first (Cloudflare evaluates account-level rulesets before zone-level ones in the same phase), then OWASP inspects what remains. | S-2, S-4 |
| FR-7 | A block is attributable in Cloudflare Security Events — matched ruleset, rule and action — filtered by the demo host. | S-1, S-2, S-3 |
| FR-8 | The action for the managed ruleset and for OWASP is configurable (`block`, `managed_challenge`, `js_challenge`, `log`) by variable, not rewrite. The managed ruleset defaults to `block`. | S-4 |
| FR-9 | OWASP sensitivity is configurable: anomaly score threshold (25/40/60) and paranoia level (1–4), each a variable change. | S-6 |
| FR-10 | The plan **fails** when the tenant or the zone is not entitled to a ruleset in use (account-level managed rulesets need Enterprise; OWASP needs Pro or higher; or the token lacks the WAF permission at that level), with a message that says why. | S-1 |
| ~~FR-11~~ | ~~The plan **fails** when a configured rule tag does not exist in the live Managed Ruleset, listing the similar tags it does have.~~ Removed 2026-10-29 with the tag-based XSS and LFI protections. | ~~S-2, S-3~~ |
| FR-12 | The plan **warns** when the hostname is not a proxied record, the origin is not locked to Cloudflare, or the demo zone is outside the managed ruleset's zone list — any of which leaves the WAF bypassed or not inspecting. | S-5 |
| FR-13 | Switching the WAF, or either ruleset, off disables its rule in place and never deletes a ruleset, with no DNS or origin change: the same URL resolves the same way, uninspected. | S-1, S-4 |
| FR-14 | The tenant-level managed ruleset's scope is configurable: every Enterprise zone in the account by default, or a named list of zones. | S-7 |

## Non-functional requirements

| ID    | Requirement | Target |
| ----- | ----------- | ------ |
| NFR-1 | Baseline-to-protected switch during a live demo | Under 60 seconds, no environment rebuild, no DNS change |
| NFR-2 | A block is self-explaining | 403 block page carries a Ray ID that matches the event-log entry |
| NFR-3 | Repeatability | The full sequence runs twice in a row with the same result |
| NFR-4 | Provider stability | Pinned to Cloudflare provider v5 (validated against 5.28.1); ruleset resources follow the v5 list-of-objects shape |

## Acceptance criteria

- [ ] WAF off: the SQLi login payload returns `200` and an `admin@juice-sh.op` token.
- [ ] WAF off: the XSS and path-traversal requests reach the origin.
- [ ] WAF on: the SQLi, XSS and path-traversal requests are each blocked (403 + Ray ID) and Security Events names the Cloudflare Managed Ruleset.
- [ ] The Cloudflare Managed Ruleset is in the account's entry point, not the zone's, with every rule enabled and the action `block`.
- [ ] With the managed ruleset disabled, the SQLi request is instead caught by the OWASP Core Ruleset; enabling it again restores the managed credit.
- [ ] Disabling and enabling either ruleset is an in-place update in the plan — nothing destroyed, nothing recreated.
- [ ] A direct request to the origin IP fails while the WAF is on (no bypass).
- [ ] With the managed ruleset disabled, changing the OWASP score threshold changes which requests are acted on.
- [ ] Enabling and disabling the WAF is a single variable with no origin or DNS change in the plan.
- [ ] Planning against a non-entitled account or zone fails with the entitlement message.

## Open questions

| Question | Owner | Resolution |
| -------- | ----- | ---------- |
| Is the committed scope final at three vectors (1.1–1.3), or do any of 1.4–1.12 come back in before the demo? | d.de.freitas.alves | Deprioritised 2026-10-26; tracked in [docs/waf-testing-plan.md](../../docs/waf-testing-plan.md). Reopen only if the RFP response needs live OWASP Top 10 breadth rather than depth. |
| Which action do we demo — `block` or `managed_challenge`? Block is cleanest on a terminal; managed challenge is more realistic and shows humans preserved. | d.de.freitas.alves | **Managed ruleset: `block`, decided 2026-10-29.** OWASP stays a variable; `managed_challenge` can still be shown once in the browser. |
| Which zones does the tenant-level managed ruleset cover? With every rule blocking, the default — every Enterprise zone in the account — also reaches zones in a shared tenant that are not part of this demo. | d.de.freitas.alves | **Open.** Tenant-wide by default, as decided 2026-10-29; narrowed with `managed_ruleset_zones` if the tenant is shared. |
| Does the OWASP Core Ruleset stay at zone level as the second layer, or move to the tenant alongside the managed ruleset? | d.de.freitas.alves | **Open.** Kept at zone level for now, scoped to the demo hostname. |
| Do we add the health-check allow rule (testing plan 2.1) to pre-empt a false-positive question, or leave it out to keep the module minimal? | | More relevant now that every managed rule blocks. |
| Which paranoia level and score threshold do we present at? PL1 / threshold 40 is the default and suits Juice Shop's JSON SPA; the false-positive demo wants a second value chosen deliberately. | | |
| Is account-level WAF active on the tenant, and is the demo zone on Enterprise, confirmed on the account and the zone themselves? Account-level managed rulesets only apply to Enterprise zones. | d.de.freitas.alves | Verify as part of `0001` zone setup before rehearsal — the plan fails without the account entitlement. |
