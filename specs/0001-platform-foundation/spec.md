# 0001 — Platform foundation

| Field     | Value |
| --------- | ----- |
| Status    | Draft |
| Owner     | d.de.freitas.alves |
| Created   | 2026-10-21 |
| Updated   | 2026-11-12 |
| AI usage  | None |

> **Note — delivered, recorded 12 November 2026.** The foundation has been
> delivered on the target domain **`pt-accenture.cftenant.com`** by
> **João Grilo**, and the domain is proxied through Cloudflare. On review, the
> architecture looks sound. Not all of it is covered by Terraform/OpenTofu yet,
> so a clean checkout cannot rebuild it on its own (FR-3, NFR-4). This spec
> stays `Draft` until the delivered architecture is written up here and the
> gap in code is closed.

> **Note — target environment, 29 October 2026.** The demo moves to the
> **Azure EBC tenant**, on the domain **`pt-accenture.cftenant.com`**. Until it
> does, the code and the PoCs run in a personal lab: the origin on GCP, behind
> the CoE's Cloudflare NFR tenant, on a personal domain (`personal-domain-1`).
> That lab is for building and rehearsing; it is not where the client sees the
> demo. The GCP implementation stays the reference until the Azure design is
> written — see Open questions.

## Summary

The disposable demo environment that every Cloudflare feature in this
repository is demonstrated on: an origin web/API application, a Cloudflare zone
in front of it, and a load generator to drive traffic — all created and
destroyed by two scripts. The origin runs on GCP today and moves to the Azure
EBC tenant, under `pt-accenture.cftenant.com`, for the client demo.

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
what its design contributed. Terraform and the two-script workflow are a given,
not an open choice. GCP was too, until the target moved to Azure on 29 October
2026; the GCP origin is now the reference the Azure one is ported from.

| | Today (lab and PoCs) | Target (client demo) |
| --- | --- | --- |
| Origin cloud | GCP, personal lab projects | Azure EBC tenant |
| Domain | `personal-domain-1` | `pt-accenture.cftenant.com` |
| Cloudflare account | CoE NFR tenant | To confirm: the account that holds `pt-accenture.cftenant.com` |

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
- The client demo is served from the target tenant and domain, not from the
  personal lab.

## Non-goals

- Production hardening of the origin. This is a demo of the edge, not of the
  cloud behind it.
- Running one demo across two clouds. The origin is on one cloud at a time: GCP
  in the lab, Azure on the target.
- CI/CD. Environments are created from a workstation.
- Any of the five edge capabilities themselves — each has its own spec.
- Keeping the MVP's multi-lab catalog framing.

## Scenarios

**S-1 — Stand up a demo environment**

- **Given** a workstation with `tofu`, the origin cloud's CLI (`gcloud` in the
  lab, `az` on the target) and a Cloudflare API token
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
| FR-2 | The script checks prerequisites and performs the origin cloud's IAM pre-flight (GCP in the lab, Azure on the target) before Terraform runs. | S-1 |
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
| NFR-5 | IaC tooling | OpenTofu ≥ 1.5, Cloudflare provider ~> 5.x. Google provider ~> 7.x for the lab; the Azure provider is pinned when the Azure origin is planned. |

## Acceptance criteria

- [ ] Bootstrap run from a clean checkout yields a reachable HTTPS hostname served through Cloudflare.
- [ ] For the client demo, that hostname is under `pt-accenture.cftenant.com` and the origin runs in the Azure EBC tenant.
- [x] `curl` against the Cloudflare hostname returns the app and the response carries Cloudflare edge headers. _(Target domain: every response in the `0006` PoC, 8–10 Nov 2026, carried a `cf-ray` header.)_
- [ ] `curl` against the origin URL directly is refused (FR-7).
- [ ] The load generator reports requests sent, and origin-side request count can be read for the same window.
- [ ] Enabling and disabling one edge feature requires no environment rebuild.
- [ ] Teardown leaves zero billable resources and an inventory under `previous-labs/<env>/` in the audit bucket.
- [ ] No tracked file contains a credential.

## Open questions

| Question | Owner | Resolution |
| -------- | ----- | ---------- |
| Which domain hosts the demo, and is it already delegated to Cloudflare? The CapAct MVP ran under `personal-domain-2`, and the current lab under `personal-domain-1`; neither is a suitable home for a client-facing RFP demo. A zone with working nameservers is a hard prerequisite for every feature. | d.de.freitas.alves | **Domain decided 2026-10-29 — `pt-accenture.cftenant.com`.** **Delivered and proxied through Cloudflare, recorded 2026-11-12** (João Grilo), which settles FR-5 on the target. API Shield, an Enterprise add-on, worked on the zone in the `0006` PoC. Still to record: which Cloudflare account holds the zone. If it is not the CoE NFR tenant, account-level configuration — the `0004` managed ruleset — has to be applied there as well. |
| Which Cloudflare plan is available? This gates the backlog: Bot Management scores and API Shield are Enterprise, Super Bot Fight Mode is Pro/Business. | d.de.freitas.alves | **Resolved 2026-10-21 — Enterprise with the Bot Management add-on**, on the CoE NFR tenant. `cf.bot_management.score`, verified-bot detection and bot analytics are all available, so `0002` and `0006` can be specified against the full feature set. To re-confirm for the account that holds the target domain. |
| How is FR-7 enforced? Cloud Run's URL is public and cannot be IP-restricted. | d.de.freitas.alves | **Resolved 2026-10-21 — shared-secret header.** Cloudflare injects a secret request header at the edge; the origin refuses anything without it. Zero added cost and no always-on infrastructure. Explicitly demo-grade: a production engagement would put the origin behind a load balancer with Cloud Armor allowlisting Cloudflare's ranges, and the demo narrative should say so rather than imply the header is the recommendation. The check lives in the app, so it carries over to Azure unchanged; the Azure counterpart of the Cloud Armor allowlist is still to be named. |
| Which Azure services replace the GCP origin on the EBC tenant — compute for the Flask app, the Firestore store, the image registry and build, the audit log sink and bucket — and who grants access to the tenant? | d.de.freitas.alves | **Answered in practice by the delivered foundation** (João Grilo, recorded 2026-11-12). Still to do: write down what it runs on, and which parts are outside Terraform/OpenTofu. Until then, `plan.md` describes the GCP implementation only. |
| Is the demo presented live against real infrastructure, or recorded? Changes how much the environment must tolerate being rebuilt on the day. | | |
