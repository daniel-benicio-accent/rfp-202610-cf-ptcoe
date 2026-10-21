# 0001 — Platform foundation

| Field     | Value |
| --------- | ----- |
| Status    | Draft |
| Owner     | d.de.freitas.alves |
| Created   | 2026-10-21 |
| Updated   | 2026-10-21 |
| AI usage  | None |

## Summary

The disposable demo environment that every Cloudflare feature in this
repository is demonstrated on: an origin web/API application on GCP, a
Cloudflare zone in front of it, and a load generator to drive traffic — all
created and destroyed by two scripts.

## Context

The RFP demo has to show this topology:

```
Internet
   │
   ▼
Cloudflare edge ── DDoS protection · WAF · Bot Management · API Security · Rate Limiting
   │
   ▼
Application (Web/API)
```

Each of the five edge capabilities is a separate feature in the backlog
(`0002`–`0006`). None of them can be built or demoed without a working origin,
a zone, and a way to generate traffic. This spec covers that shared base.

We are not starting from zero. An earlier CoE lab-platform MVP, **MyCapAct**,
kickstarted this work: its first lab deployed a suitable origin — a Flask
whiteboard on Cloud Run with both a browser UI and a REST API — wrapped in a
bootstrap/teardown script pair with an audit trail. That MVP lives in a separate
project and is not a dependency here;
[docs/inherited-from-capact.md](../../docs/inherited-from-capact.md) records
what its design contributed. The decision to keep GCP, Terraform and the
two-script workflow is a given, not an open choice.

What must change is how that code is organized. The MVP's bootstrap script
generates the application and all Terraform from roughly 1100 lines of embedded
heredocs. That is acceptable for a self-contained training lab handed out as one
file; it is wrong here, because this repository is the deliverable. Source
emitted from a heredoc cannot be reviewed, diffed, traced to a spec, or edited
per feature.

## Goals

- One command creates a complete, working demo environment; one destroys it.
- The origin application and all Terraform are tracked, reviewable files.
- Each of the five edge features can be switched on and off independently, so a
  demo can show before/after for one capability at a time.
- Traffic reaching the origin is observable, so "the edge stopped it" is backed
  by evidence rather than assertion.
- Idle cost stays near zero.

## Non-goals

- Production hardening of the origin. This is a demo of the edge, not of GCP.
- Multi-cloud. GCP only.
- CI/CD. Environments are created from a workstation.
- Any of the five edge capabilities themselves — each has its own spec.
- Keeping the MVP's multi-lab catalog framing.

## Scenarios

**S-1 — Stand up a demo environment**

- **Given** a workstation with `gcloud`, `tofu` and a Cloudflare API token
- **When** the operator runs the bootstrap script and answers its prompts
- **Then** a uniquely named environment is scaffolded, and after applying
  Terraform the application is reachable over HTTPS at a Cloudflare-proxied
  hostname

**S-2 — Demonstrate one capability**

- **Given** a running environment with all edge features off
- **When** the presenter enables a single feature and re-runs the same traffic
- **Then** the change in what reaches the origin is visible side by side

**S-3 — Prove the edge cannot be bypassed**

- **Given** a running environment
- **When** a request is sent straight to the origin URL, skipping Cloudflare
- **Then** it is refused

**S-4 — Tear down**

- **Given** a finished demo
- **When** the operator runs the teardown script and confirms by typing the
  environment name
- **Then** every cloud resource is destroyed and an inventory of what existed is
  preserved in the audit bucket

## Functional requirements

| ID | Requirement | Scenario |
| ---- | ----------- | -------- |
| FR-1 | A bootstrap script scaffolds a uniquely named environment (`<prefix>-<unix-epoch>`) so several can run in parallel. | S-1 |
| FR-2 | The script checks prerequisites and performs the GCP IAM pre-flight before Terraform runs. | S-1 |
| FR-3 | The origin application and Terraform are tracked files under `src/`. Bootstrap renders only per-environment configuration. | S-1 |
| FR-4 | The origin exposes both a browser UI and a REST API on the same hostname. | S-2 |
| FR-5 | A Cloudflare-proxied DNS record points at the origin, terminating TLS at the edge. | S-1 |
| FR-6 | Edge features are independently toggleable without destroying the environment. | S-2 |
| FR-7 | Requests that bypass Cloudflare and hit the origin directly are refused. | S-3 |
| FR-8 | A load generator produces configurable HTTP traffic against the hostname and reports requests sent. | S-2 |
| FR-9 | Requests arriving at the origin are countable, so sent-vs-arrived can be compared. | S-2 |
| FR-10 | Teardown inventories all resources, uploads the inventory to the audit bucket, then destroys the environment. | S-4 |
| FR-11 | Teardown requires the operator to type the environment name. | S-4 |
| FR-12 | The audit bucket is created outside Terraform and survives teardown. | S-4 |

## Non-functional requirements

| ID | Requirement | Target |
| ----- | ----------- | ------ |
| NFR-1 | Idle cost | Near zero. Scale-to-zero compute and no always-on load balancer — the FR-7 decision keeps it that way. |
| NFR-2 | Time from bootstrap to reachable application | Under 20 minutes, unattended after the prompts. |
| NFR-3 | No secrets in the repository | Cloudflare API token and the FR-7 edge secret both come from the environment. No credentials in tracked files. |
| NFR-4 | Reproducibility | A clean checkout plus the documented prerequisites is enough. |
| NFR-5 | IaC tooling | OpenTofu ≥ 1.5, Google provider ~> 7.x, Cloudflare provider ~> 5.x. |

## Acceptance criteria

- [ ] Bootstrap run from a clean checkout yields a reachable HTTPS hostname served through Cloudflare.
- [ ] `curl` against the Cloudflare hostname returns the app and the response carries Cloudflare edge headers.
- [ ] `curl` against the origin URL directly is refused (FR-7).
- [ ] The load generator reports requests sent, and origin-side request count can be read for the same window.
- [ ] Enabling and disabling one edge feature requires no environment rebuild.
- [ ] Teardown leaves zero billable resources and an inventory under `previous-labs/<env>/` in the audit bucket.
- [ ] No tracked file contains a credential.

## Open questions

| Question | Owner | Resolution |
| -------- | ----- | ---------- |
| Which domain hosts the demo, and is it already delegated to Cloudflare? The CapAct MVP ran under `personal-domain-2`, which is not a suitable home for a client-facing RFP demo — a practice-owned zone is probably needed. A zone with working nameservers is a hard prerequisite for every feature. | d.de.freitas.alves | **Open.** Blocks FR-5 and therefore the whole backlog. |
| Which Cloudflare plan is available? This gates the backlog: Bot Management scores and API Shield are Enterprise, Super Bot Fight Mode is Pro/Business. | d.de.freitas.alves | **Resolved 2026-10-21 — Enterprise with the Bot Management add-on.** `cf.bot_management.score`, verified-bot detection and bot analytics are all available, so `0002` and `0006` can be specified against the full feature set. |
| How is FR-7 enforced? Cloud Run's URL is public and cannot be IP-restricted. | d.de.freitas.alves | **Resolved 2026-10-21 — shared-secret header.** Cloudflare injects a secret request header at the edge; the origin refuses anything without it. Zero added cost and no always-on infrastructure. Explicitly demo-grade: a production engagement would put the origin behind a load balancer with Cloud Armor allowlisting Cloudflare's ranges, and the demo narrative should say so rather than imply the header is the recommendation. |
| Is the demo presented live against real infrastructure, or recorded? Changes how much the environment must tolerate being rebuilt on the day. | | |
