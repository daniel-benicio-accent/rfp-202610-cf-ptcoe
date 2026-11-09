# Specifications

Live, prioritized backlog of every specification in this repository, the
components that implement each one, and the cross-cutting tasks around them.
Add a row when you create a spec or take on a task; update the status as it
moves; list a component in its spec's row as it lands. The workflow and status
values are described in [../docs/spec-workflow.md](../docs/spec-workflow.md).

## Contents

- [Prioritized backlog](#prioritized-backlog)
- [Dependencies](#dependencies)
- [Creating a spec](#creating-a-spec)

## Prioritized backlog

Bot management first, by owner decision. The rest are ordered by effort against
demo value — cheapest convincing demo next. `0001` comes before all of them: it
is the foundation every feature depends on.

> **Note:** struck-through rows are out of scope. Bot Management and API Security
> were struck on 26 October 2026 and **reinstated on 29 October 2026, when RFP
> requirements were last updated** — Bot Management as a mandatory requirement
> (expanded to brute-force, scraping, spam, automated form abuse, account
> takeover and credential stuffing) and API Security as a progressive
> capability. Rate limiting stays out as a standalone feature: it is now folded
> into Bot Management and API Security.

| # | ID | Feature | Status | Effort | Demo value | Why here | AI usage | Links | Components |
| - | -- | ------- | ------ | ------ | ---------- | -------- | -------- | ----- | ---------- |
| 0 | 0001 | **Platform foundation** | Draft | — | — | Prerequisite for everything below: delivers the origin, the proxied hostname, the load generator and the origin lockdown that stops the edge being bypassed — see [Dependencies](#dependencies). | None | [spec](0001-platform-foundation/spec.md) · [plan](0001-platform-foundation/plan.md) · [tasks](0001-platform-foundation/tasks.md) | [gcp template](../src/terraform/_templates/gcp/) — origin: Cloud Run, Firestore, Artifact Registry, Cloud Build, audit log sink. _Written, schema-validated against the google provider._<br>[zone template](../src/terraform/_templates/zone/) — proxied record, Host header rewrite, edge secret injection. _Written, schema-validated against cloudflare 5.28.1. TLS mode still a TODO._<br>[bootstrap-terraform.sh](../scripts/bootstrap-terraform.sh) — wizard that renders a complete demo into `demos/<name>/`, and creates the audit bucket. _Working. IAM pre-flight still open — see task 6b._<br>[project-verify.sh](../scripts/project-verify.sh) — read-only check of a demo's resources and live behaviour. _Working, exercised against a real deployment._<br>[project-nuke.sh](../scripts/project-nuke.sh) — teardown: inventory, audit upload, ordered destroy. _Working. Ordering and skip logic tested; cloud calls not yet exercised._<br>[src/app/](../src/app/) — Flask whiteboard: browser UI plus REST API, edge-secret check (FR-7), arrival counter (FR-9). _Deployed and verified on Cloud Run: direct requests get 403, header requests get 200._<br>`src/load-generator/` — Vegeta-based traffic and bot simulator with Prometheus metrics. _Not started._ |
| 1 | 0002 | **Bot management** | **WIP**🟢 | Medium | High | **Mandatory requirement (29 Oct 2026).** Owner priority, and the best-understood of the five — the CapAct MVP's first lab was "Cloudflare Bot Handling". Expanded to cover brute-force, scraping, spam, automated form abuse, account takeover and credential stuffing, with per-application tuning and monitoring. | Vendor-side ML | [spec](0002-bot-management/spec.md) · [plan](0002-bot-management/plan.md) · [tasks](0002-bot-management/tasks.md) | [feature template](../src/terraform/_templates/feature/) — generic edge-feature module behind an `enable_<feature>` toggle, shared by `0002` onward. _Skeleton. Phase and match expression are per-feature TODOs._ |
| 2 | 0004 | **WAF** | **PoC done**🟢 | Low–medium | High | Managed rulesets plus a custom rule. A single SQLi payload demonstrates it; core to any Cloudflare bid. Minimum viable lab already running against OWASP Juice Shop. | None | [spec](0004-waf/spec.md) · [plan](0004-waf/plan.md) · [tasks](0004-waf/tasks.md) · [testing plan](../docs/waf-testing-plan.md) | [demos/wafdemo-owasp-juice-shop/](../demos/wafdemo-owasp-juice-shop/) — hand-written WAF demo (not a template): Juice Shop on a GCE VM behind Cloudflare, with the Cloudflare Managed Ruleset at tenant level (every rule blocking) and the OWASP Core Ruleset at zone level, behind `enable_waf`. _PoC done — module written; before/after flow documented in the [runbook](../docs/wafdemo-owasp-juice-shop.md). The XSS/LFI managed protections were dropped on 29 Oct 2026: no longer available._ |
| 3 | 0005 | **DDoS protection** | **TO SPECIFY REQUIREMENTS**🔴 <br>**WIP**🟢 | Low to configure, high to demo | Medium | Managed rulesets are largely on by default, so configuration is trivial — but a real volumetric attack cannot be launched, so the demo is mostly dashboard narration. Value is in the RFP answer more than the live show. A PoC with mTLS support is in progress. | — | [spec](0005-ddos-protection/spec.md) · [plan](0005-ddos-protection/plan.md) · [tasks](0005-ddos-protection/tasks.md) | [demos/demohpingkali/](../demos/demohpingkali/) — public GKE cluster as a many-source traffic generator: one Kali/hping pod per node, each node its own public IP, node count driven by `hping_min_replicas`. _PoC deployed. spec.md still a stub — requirements not yet written._ |
| 4 | 0006 | **API security** | Draft | High | High | **Progressive capability requirement (29 Oct 2026):** API discovery and inventory, API-specific WAF policies, mTLS, schema validation, API-specific rate limiting and anomalous-traffic protection. A path exists on top of the WAF lab, targeting the Juice Shop REST API and the CTFd event API. | Vendor-side ML | [spec](0006-api-security/spec.md) · [plan](0006-api-security/plan.md) · [tasks](0006-api-security/tasks.md) | — |
| ~~—~~ | ~~0003~~ | ~~**Rate limiting**~~ | ~~Backlog~~ | ~~Low~~ | ~~High~~ | ~~Folded into Bot Management (brute-force, credential stuffing) and API Security (API-specific rate limiting) by the 29 Oct 2026 update; no longer a standalone feature.~~ | — | ~~not scaffolded~~  <br>_This requirement was merged into API Security part_ | — |
| — | task | **Deploy infra on the Azure EBC tenant and domain `pt-accenture.cftenant.com`** | **WIP**🟢 | — | — | Target environment for the demo. Today the code and the PoC run in a personal lab on GCP behind the CoE's Cloudflare NFR tenant. | — | — | — |
| — | task | **Migrate all backlog into the GitHub project view** | **TO PRIORITIZE**🟢 | — | — | — | — | [project view](https://github.com/users/daniel-benicio-accent/projects/1/views/2) | — |

Component state is in italics. The Terraform templates are rendered into each
demo as its own copy; the WAF demo is the exception, written by hand.

`0005` is agreed scope but not yet written. Scaffold it when it comes up the
backlog, so numbers stay sequential and nothing sits half-specified.

## Dependencies

`0001` gates everything. Until there is a Cloudflare-proxied hostname and an
origin that refuses direct traffic, no edge feature can be demonstrated
honestly — a "blocked" request could just be retried against the origin URL.

```
0001 ──┬── 0002  bot management
       ├── 0003  rate limiting
       ├── 0004  WAF
       ├── 0005  DDoS protection
       └── 0006  API security
```

## Creating a spec

```powershell
./scripts/new-spec.ps1 -Title "Rate limiting"
```

```bash
./scripts/new-spec.sh "Rate limiting"
```

Both scaffold `specs/NNNN-slug/` with `spec.md`, `plan.md` and `tasks.md` from
[_templates/](_templates/), numbered sequentially.
