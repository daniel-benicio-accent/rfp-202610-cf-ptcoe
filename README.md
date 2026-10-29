# rfp-202610-cf-ptcoe

Central repository for the **Cloudflare RFP demo (October 2026)**, built by the
Accenture Portugal Center of Excellence.

## Purpose

RFP demos tend to scatter across laptops, chat threads and short-lived
sandboxes, and disappear once the bid is submitted. This repository centralizes
**all source code, infrastructure and documentation** produced for this RFP, so
that:

- the demo is reproducible from a clean checkout, by anyone on the team;
- every component traces back to a written, approved specification;
- the work survives the bid and can be reused or handed over.

The project is **spec-driven**: specifications are the source of truth and code
is written to satisfy them, never the other way around. Nothing gets built
before its spec is approved.

## Contents

- [What the demo shows](#what-the-demo-shows)
- [Key decisions](#key-decisions)
- [Repository map](#repository-map)
  - [Source layout](#source-layout)
- [Quick start](#quick-start)
  - [Start a new piece of work](#start-a-new-piece-of-work)
  - [Create a demo](#create-a-demo)
  - [Apply a demo](#apply-a-demo)
  - [Verify a demo](#verify-a-demo)
  - [Destroy a demo](#destroy-a-demo)
- [Conventions](#conventions)

## What the demo shows

```
Internet
   │
   ▼
┌──────────────────────────────────────────────┐
│              Cloudflare edge                 │
│                                              │
│   DDoS protection · WAF · Bot Management      │
│   API Security · Rate Limiting               │
└──────────────────────────────────────────────┘
   │
   ▼
Application (Web / API)   — Cloud Run + Firestore on GCP
```

> **Note:** Currently all we have are some codes and a PoC running in a personal lab on GCP and personal domain over CoE's Cloudflare NFR tenant. Check specs Readme for the status on move into Azure EBC tenant and domain pt-accenture.cftenant.com .  

Each of the five edge capabilities is a separate feature with its own
specification, demonstrated independently: same request, accepted before and
refused after, with a reason attached. Which ones are in scope, in what order,
and how far each has got: [specs/README.md](specs/README.md#prioritized-backlog).

The origin, the environment lifecycle and the traffic simulator build on
**MyCapAct**, an earlier CoE lab-platform MVP that was used to kickstart this
work. It lives in a separate project and is not a dependency — what it
contributed is recorded in
[docs/inherited-from-capact.md](docs/inherited-from-capact.md), and anything
reused is reimplemented here as tracked code.

## Key decisions

| Decision | Value | Consequence |
| --- | --- | --- |
| Cloudflare plan | Enterprise, with the Bot Management add-on | Bot score, verified-bot detection and bot analytics are all available, so `0002` is specified against the full product rather than Super Bot Fight Mode. |
| Origin lockdown | Shared-secret header injected at the edge, checked by the origin | Keeps idle cost at zero and needs no always-on load balancer. **Demo-grade on purpose** — the production recommendation is Cloud Armor allowlisting Cloudflare's ranges, and the demo narrative must say so. |

Still open and blocking: **which domain hosts the demo, and is it delegated to
Cloudflare?** Nothing downstream can start without a zone. The labs currently
run in a personal Cloudflare/GCP environment; moving them to the target **Azure
EBC** environment is pending and tracked per spec.

## Repository map

| Path | What lives here |
| --- | --- |
| [specs/README.md](specs/README.md) | Backlog, index and status of every specification, and the components that implement each. **Start here.** |
| [specs/](specs/) | One folder per feature: `NNNN-slug/` with `spec.md`, `plan.md`, `tasks.md`. |
| [specs/_templates/](specs/_templates/) | Templates the spec scaffolder copies from. |
| [src/terraform/_templates/](src/terraform/_templates/) | The only Terraform kept in the repo. Everything else is rendered per demo. |
| `demos/<name>/` | One self-contained demo, rendered by the wizard. Not present until you create one. |
| [scripts/](scripts/) | Repository tooling: spec scaffolder, demo wizard, teardown. |
| [docs/spec-workflow.md](docs/spec-workflow.md) | The spec → plan → tasks → code lifecycle and status values. |
| [docs/conventions.md](docs/conventions.md) | Working agreements: language, naming, documentation, AI tooling, secrets. |
| [docs/prerequisites.md](docs/prerequisites.md) | Workstation setup: WSL, OpenTofu, `gcloud`, and the environment variables. |
| [docs/created-objects.md](docs/created-objects.md) | Checklist of every object a demo creates, for walking the consoles by hand. |
| [docs/wafdemo-owasp-juice-shop.md](docs/wafdemo-owasp-juice-shop.md) | Runbook for the hand-written WAF demo: Juice Shop on a GCE VM behind Cloudflare. |
| [docs/waf-testing-plan.md](docs/waf-testing-plan.md) | WAF test cases mapped to the OWASP Top 10:2025, with deprioritized items struck through. Backs spec [0004](specs/0004-waf/spec.md). |
| [docs/inherited-from-capact.md](docs/inherited-from-capact.md) | What the CapAct MVP contributed to this work, and why. History, not a dependency. |

This file and [specs/README.md](specs/README.md) are the only two READMEs in the
repository, by convention. Detail that would go in a component README belongs
either in `docs/` or as a comment next to the code it explains — see
[docs/conventions.md](docs/conventions.md#where-documentation-lives).

### Source layout

`src/` holds what is shared across demos. Terraform instances are **not** kept
here — each demo gets its own, rendered by the wizard.

```
src/
├── app/                      origin application (Flask) — not created yet, spec 0001 task 4
├── load-generator/           traffic and bot simulator — not created yet, spec 0001 task 11
└── terraform/_templates/
    ├── gcp/                  origin infrastructure
    ├── zone/                 proxied record, Host rewrite, edge secret injection
    └── feature/              one edge capability, parameterised by spec and slug

demos/<name>/                one demo, rendered from the above
├── .envconfig                metadata, read by project-nuke.sh
├── app/                      this demo's copy of the application
└── terraform/
    ├── gcp/
    └── cloudflare/{zone,<feature>}/
```

Several demos can run in parallel in different GCP projects and on different
hostnames, sharing nothing but the templates they came from.

## Quick start

```bash
git clone git@github.com:daniel-benicio-accent/rfp-202610-cf-ptcoe.git rfp-202610-cf-ptcoe
cd rfp-202610-cf-ptcoe
cat specs/README.md     # what exists and where it stands
```

Check dev lab prerequisites in [docs/prerequisites.md#install-steps](docs/prerequisites.md#install-steps) — WSL, OpenTofu and `gcloud`. Two environment variables are also required, and
neither is ever written to a tracked file:

| Variable | What it is |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Scoped to edit the demo zone |
| `TF_VAR_edge_secret` | The shared secret the edge injects and the origin checks; generated per environment |

A Cloudflare zone is also required and is the one remaining blocking question on
`0001`.

### Start a new piece of work

Scaffold the spec folder — the number is allocated automatically:

```powershell
# Windows PowerShell
./scripts/new-spec.ps1 -Title "Rate limiting"
```

```bash
# macOS, Linux, Git Bash
./scripts/new-spec.sh "Rate limiting"
```

Both produce:

```
specs/0003-rate-limiting/
├── spec.md     what and why
├── plan.md     how
└── tasks.md    the breakdown
```

Then:

1. Fill in `spec.md`. Requirements only — no implementation detail.
2. Register it in [specs/README.md](specs/README.md).
3. Get it reviewed and set `Status: Approved`.
4. Write `plan.md` and `tasks.md`.
5. Build under `src/<component>/`, and list the component in its spec's row in
   [specs/README.md](specs/README.md).

### Create a demo

One wizard call produces a complete, ready-to-apply demo under `demos/<name>/`:

```bash
./scripts/bootstrap-terraform.sh
```

It asks for the demo name, GCP project, region, audit bucket, Cloudflare zone
and hostname, and which edge feature modules to include (`<spec-id>:<slug>`,
space-separated). Everything can also be passed as flags, which is how you
repeat a known-good demo:

```bash
./scripts/bootstrap-terraform.sh --non-interactive   --name cfdemo-001 --project my-gcp-project   --zone-id <zone> --domain example.com --subdomain demo   --feature 0002:bot-management --feature 0003:rate-limiting
```

Re-running against an existing demo never overwrites a file. Run
`./scripts/bootstrap-terraform.sh --help` for the full option list.

**Versioning a demo folder is your choice.** Commit one when you want a record
of exactly what a given demo was; leave it alone otherwise. Local state and
`.envconfig` are never committed, so a committed folder is a record rather than
a working handle — without the state nobody else can apply or destroy it.

### Apply a demo

```bash
export CLOUDFLARE_API_TOKEN="..."                  # zone edit scope
export TF_VAR_edge_secret="$(openssl rand -hex 24)"

cd demos/<name>/terraform/gcp
tofu init && tofu plan -out=tfplan && tofu apply tfplan
tofu output -raw service_url                       # strip https://, see next step
```

Put that hostname into `terraform/cloudflare/zone/terraform.tfvars` as
`origin_hostname`, then:

```bash
cd ../cloudflare/zone
tofu init && tofu apply
```

Enable one edge feature at a time, without rebuilding anything:

```bash
cd ../bot-management
tofu apply -var 'enable_bot_management=true'
```

Always capture the baseline with the feature **off** first — showing before and
after is the whole point.

Then verify the edge is really in the path and cannot be skipped:

```bash
curl -sI https://<hostname> | grep -i cf-ray     # served through Cloudflare
curl -sI https://<cloud-run-url>                 # must be refused (spec 0001 FR-7)
```

Two things that will bite you, both documented in the code at the point they
matter:

- **`tofu validate` in `gcp/` fails with four `filesha256` errors** if the
  demo has no `app/` folder. The module hashes the application sources to decide
  when to rebuild the image, so each demo carries its own copy. Re-run the
  wizard with the same `--name` to copy `src/app/` in; it skips everything that
  already exists.
- **Cloud Run routes by Host header.** A proxied CNAME forwards the visitor's
  Host, matches no service, and the origin answers 404 — looking exactly like
  broken DNS. The zone module's origin rule rewrites Host to the `*.run.app`
  name. Do not remove it.

### Verify a demo

Terraform reports what it managed to create. It says nothing about what it
never tried, what was changed by hand, or whether the thing actually behaves.
This asks the cloud and the running service directly:

```bash
./scripts/project-verify.sh <name>
```

It checks the enabled APIs, the service account, registry, Firestore, Cloud Run
service, audit bucket and log sink; then the live behaviour — a direct request
is refused with 403 (FR-7), `/health` answers without the header, the app is
served when the header is present, `/api/stats` reports arrivals (FR-9); then
the edge, if the zone is applied. Read-only, and it exits non-zero on any
failure so it can gate a rehearsal.

Each failure comes with the command that fixes it.

### Destroy a demo

A running demo costs money every hour. Tear it down the same day:

```bash
./scripts/project-nuke.sh --list          # what exists
./scripts/project-nuke.sh <name>          # inventory, audit, destroy
```

It asks you to type the demo name, inventories what exists, uploads that
inventory to the audit bucket under `previous-labs/<name>/`, then destroys in
dependency order: **feature modules, then the zone, then GCP.** That is the
reverse of creation. Going the other way would leave a proxied hostname
pointing at a dead origin and strand the Cloudflare state — and because each
module keeps its own state, nothing enforces the order for you.

The audit bucket itself is created outside Terraform and survives teardown, so
the record of what existed outlives the demo.

## Conventions

Everything written here — specs, docs, code, comments, commit messages — is in
**English**, whatever language the conversation happens in. Full list in
[docs/conventions.md](docs/conventions.md).
