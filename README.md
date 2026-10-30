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

Each of the five edge capabilities is a separate feature with its own
specification, demonstrated independently: same request, accepted before and
refused after, with a reason attached.

The origin, the environment lifecycle and the traffic simulator build on
**MyCapAct**, an earlier CoE lab-platform MVP that was used to kickstart this
work. It lives in a separate project and is not a dependency — what it
contributed is recorded in
[docs/inherited-from-capact.md](docs/inherited-from-capact.md), and anything
reused is reimplemented here as tracked code.

## Backlog

Bot management first, by owner decision. The rest are ordered by effort against
demo value — cheapest convincing demo next.

| # | Spec | Feature | Effort | Demo value | Why here |
| - | ---- | ------- | ------ | ---------- | -------- |
| 1 | [0002](specs/0002-bot-management/spec.md) | **Bot management** | Medium | High | Owner priority. Also the best-understood of the five — the CapAct MVP's first lab was "Cloudflare Bot Handling", so the origin shape and the bot simulation method are already proven. |
| 2 | 0003 | **Rate limiting** | Low | High | One ruleset resource. The load generator we already have makes the before/after obvious and quantifiable. |
| 3 | 0004 | **WAF** | Low–medium | High | Managed rulesets plus a custom rule. A single SQLi payload demonstrates it; core to any Cloudflare bid. |
| 4 | 0005 | **DDoS protection** | Low to configure, high to demo | Medium | Managed rulesets are largely on by default, so configuration is trivial — but a real volumetric attack cannot be launched, so the demo is mostly dashboard narration. Value is in the RFP answer more than the live show. |
| 5 | 0006 | **API security** | High | High | API Shield is available on our tier, but it still needs an OpenAPI schema, endpoint discovery and schema validation to show anything. Highest effort of the five. |

All five depend on **[0001 Platform foundation](specs/0001-platform-foundation/spec.md)**,
which delivers the origin, the proxied hostname, the load generator and the
origin lockdown that stops the edge being bypassed.

Status for every spec: [specs/README.md](specs/README.md).

### Decisions taken

| Decision | Value | Consequence |
| --- | --- | --- |
| Cloudflare plan | Enterprise, with the Bot Management add-on | Bot score, verified-bot detection and bot analytics are all available, so `0002` is specified against the full product rather than Super Bot Fight Mode. |
| Origin lockdown | Shared-secret header injected at the edge, checked by the origin | Keeps idle cost at zero and needs no always-on load balancer. **Demo-grade on purpose** — the production recommendation is Cloud Armor allowlisting Cloudflare's ranges, and the demo narrative must say so. |

Still open and blocking: **which domain hosts the demo, and is it delegated to
Cloudflare?** Nothing downstream can start without a zone.

## Repository map

| Path | What lives here |
| --- | --- |
| [specs/README.md](specs/README.md) | Index and status of every specification. **Start here.** |
| [specs/](specs/) | One folder per feature: `NNNN-slug/` with `spec.md`, `plan.md`, `tasks.md`. |
| [specs/_templates/](specs/_templates/) | Templates the spec scaffolder copies from. |
| [src/terraform/_templates/](src/terraform/_templates/) | The only Terraform kept in the repo. Everything else is rendered per demo. |
| `demos/<name>/` | One self-contained demo, rendered by the wizard. Not present until you create one. |
| [scripts/](scripts/) | Repository tooling: spec scaffolder, demo wizard, teardown. |
| [docs/spec-workflow.md](docs/spec-workflow.md) | The spec → plan → tasks → code lifecycle and status values. |
| [docs/conventions.md](docs/conventions.md) | Working agreements: language, naming, documentation, AI tooling, secrets. |
| [docs/prerequisites.md](docs/prerequisites.md) | Workstation setup: WSL, OpenTofu, `gcloud`, and the environment variables. |
| [docs/created-objects.md](docs/created-objects.md) | Checklist of every object a demo creates, for walking the consoles by hand. |
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
5. Build under `src/<component>/`, and add the component to the table below.

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

## Components

Listed as they land, each linked to the spec it implements. The Terraform
entries are templates; each demo gets its own rendered copy.

| Component | Spec | What it is | State |
| --- | --- | --- | --- |
| [terraform/_templates/gcp/](src/terraform/_templates/gcp/) | [0001](specs/0001-platform-foundation/spec.md) | Origin: Cloud Run, Firestore, Artifact Registry, Cloud Build, audit log sink. | Written, schema-validated against the google provider. |
| [terraform/_templates/zone/](src/terraform/_templates/zone/) | [0001](specs/0001-platform-foundation/spec.md) | Proxied record, Host header rewrite, edge secret injection. | Written, schema-validated against cloudflare 5.28.1. TLS mode still a TODO. |
| [terraform/_templates/feature/](src/terraform/_templates/feature/) | [0002](specs/0002-bot-management/spec.md) onward | Generic edge-feature module behind an `enable_<feature>` toggle. | Skeleton. Phase and match expression are per-feature TODOs. |
| [scripts/bootstrap-terraform.sh](scripts/bootstrap-terraform.sh) | [0001](specs/0001-platform-foundation/spec.md) | Wizard that renders a complete demo into `demos/<name>/`, and creates the audit bucket. | Working. IAM pre-flight still open — see `0001` task 6b. |
| [scripts/project-verify.sh](scripts/project-verify.sh) | [0001](specs/0001-platform-foundation/spec.md) | Read-only check of a demo's resources and live behaviour. | Working, exercised against a real deployment. |
| [scripts/project-nuke.sh](scripts/project-nuke.sh) | [0001](specs/0001-platform-foundation/spec.md) | Teardown: inventory, audit upload, ordered destroy. | Working. Ordering and skip logic tested; cloud calls not yet exercised. |
| [src/app/](src/app/) | [0001](specs/0001-platform-foundation/spec.md) | Flask whiteboard: browser UI plus REST API, edge-secret check (FR-7), arrival counter (FR-9). | Deployed and verified on Cloud Run: direct requests get 403, header requests get 200. |
| [src/load-generator/](src/load-generator/) | [0002](specs/0002-bot-management/spec.md) | Bounded, one-shot container CLI for six synthetic Bot Management scenarios. | Implemented; local unit tests available. |

## Conventions

Everything written here — specs, docs, code, comments, commit messages — is in
**English**, whatever language the conversation happens in. Full list in
[docs/conventions.md](docs/conventions.md).
