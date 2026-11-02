# 0001 — Platform foundation — Plan

> Draft proposal. The approach below (GCP, OpenTofu, the bootstrap/nuke script
> pair) was set by the project owner, so it is recorded here ahead of spec
> approval. Nothing is built until `spec.md` reaches `Approved`.
>
> **Target moved, 29 October 2026:** the client demo runs in the Azure EBC
> tenant under `pt-accenture.cftenant.com`. Everything below describes the GCP
> implementation the lab runs on, which is the reference for the Azure port.
> The Azure design is written once the spec's open question on Azure services
> is answered.

| Field   | Value |
| ------- | ----- |
| Status  | Draft |
| Updated | 2026-10-29 |

## Approach

Keep the wizard-and-teardown lifecycle proven in the CapAct MVP, and change
only where the generated source comes from. In the MVP the Terraform lived as
heredocs inside the script, so it could never be reviewed or diffed. Here the
source of truth is a set of template files under `src/terraform/_templates/`,
and `bootstrap-terraform.sh` is a wizard that gathers one demo's parameters and
renders those templates into `demos/<name>/` along with `terraform.tfvars` and
`.envconfig`.

Each demo is self-contained, so several can run in parallel across different
GCP projects and hostnames, sharing nothing but the templates. Whether a demo
folder is committed is the operator's call: commit one as a record of what a
given demo was, or leave it alone. Local state and `.envconfig` are never
committed either way, which makes a committed folder a record rather than a
working handle.

Edge features are separate OpenTofu modules under
`demos/<name>/terraform/cloudflare/`, each behind an `enable_*` boolean, so a
presenter can flip one capability with a targeted apply and no rebuild.

Origin lockdown (FR-7) is the shared-secret header decided on 2026-10-21. A
Cloudflare transform rule adds a secret request header on every proxied request;
the Flask app returns 403 when the header is absent or wrong. The secret is a
single value held in one place — `TF_VAR_edge_secret` in the operator's
environment — and flows to both sides from there: into the transform rule, and
into the Cloud Run service as an environment variable. Nothing is written to a
tracked file.

This is a demo-grade control and the demo script should say so out loud. It
proves the topology is not bypassable *for the purposes of the demo*; it is not
what we would propose to a client, because anyone who learns the header value
can replay it. The production answer is a load balancer with Cloud Armor
allowlisting Cloudflare's published ranges, and that belongs in the RFP response
text even though it is not what the demo runs on.

## Alternatives considered

| Option | Why not |
| ------ | ------- |
| Keep generating everything from heredocs | The repository is the deliverable. Heredoc-emitted source cannot be reviewed, diffed or traced to a spec. |
| One flat Terraform root for GCP and Cloudflare | Makes per-feature toggling a matter of commenting out resources. Separate modules keep FR-6 cheap. |
| Remote state (TFE, GCS backend) | Overhead for a short-lived demo. Local state, as in the MVP. Revisit if the demo becomes shared. |
| Rewrite the origin app | It already has the browser and REST surfaces the features need. Changing it costs effort and buys nothing. |

## Target structure

```
src/
├── app/                        origin application (shape taken from the MVP)
│   ├── main.py                 Flask; plus edge-secret check (FR-7) and request counter (FR-9)
│   ├── requirements.txt
│   ├── Dockerfile
│   └── templates/whiteboard.html
├── load-generator/             Vegeta-based, from the MVP's second generation
└── terraform/
    ├── gcp/                    origin: APIs, Artifact Registry, Firestore,
    │                           SA and IAM, Cloud Build, Cloud Run, log sink
    └── cloudflare/
        ├── zone/               proxied DNS record, TLS mode (FR-5)
        ├── bot-management/     spec 0002
        ├── rate-limiting/      spec 0003
        ├── waf/                spec 0004
        ├── ddos/               spec 0005
        └── api-security/       spec 0006
scripts/
├── bootstrap-terraform.sh      wizard, renders into demos/<name>/
└── project-nuke.sh             inventory, audit, ordered destroy
envs/                           gitignored: per-environment config and local state
```

## Components

| Component | Path | Responsibility |
| --------- | ---- | -------------- |
| Origin app | `src/app/` | Serves the UI and API. Rejects requests without the edge secret. Counts arrivals. |
| GCP module | `_templates/gcp/` | The origin infrastructure as proven in the MVP, including the `time_sleep` waits. Rendered to `demos/<name>/terraform/gcp/`. |
| Zone module | `_templates/zone/` | Proxied record, TLS mode, edge secret header injection. Rendered to `demos/<name>/terraform/cloudflare/zone/`. |
| Feature modules | `_templates/feature/` | One rendering per backlog item, each behind `enable_<feature>`, parameterised by spec id and slug. |
| Load generator | `src/load-generator/` | Vegeta attack engine and Prometheus; reports requests sent. |
| Demo wizard | `scripts/bootstrap-terraform.sh` | Prompts for one demo's parameters and renders a complete tree into `demos/<name>/`. Never overwrites. GCP pre-flight still to add (task 6b). |
| Teardown | `scripts/project-nuke.sh` | Typed confirmation, inventory, audit upload, then destroy in dependency order: features, zone, GCP. |

## Stack and dependencies

- OpenTofu >= 1.5, providers `hashicorp/google ~> 7.0`, `cloudflare/cloudflare ~> 5.0`, `null`, `time`
- `gcloud` CLI, authenticated with Application Default Credentials
- Cloudflare **Enterprise** zone with the Bot Management add-on
- `CLOUDFLARE_API_TOKEN` in the environment, scoped to edit the demo zone
- `TF_VAR_edge_secret` in the environment — the FR-7 shared secret, generated per environment
- Region `europe-west1`
- Python 3.12, Flask and Gunicorn for the origin; Vegeta for load

## Interfaces and data

- Origin endpoints: `GET /`, `GET /api/message`, `POST /api/message`, `GET /health`, plus a counter endpoint for FR-9.
- Firestore Native: collection `whiteboard`, document `current`, field `text`.
- Audit bucket layout: `previous-labs/<demo>/nuke-<ts>.log`.
- `.envconfig` keys: environment name, project, region, audit bucket, zone, hostname, submitter principal, compute SA.

## Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| Target zone `pt-accenture.cftenant.com` not yet active on Cloudflare, or held in an unexpected account | Blocks the whole backlog on the target | Domain decided 2026-10-29; confirm the zone's status, account and plan before anything else. Everything downstream waits on it. |
| The Azure port is not ready by the demo date | The demo would have to run on the personal lab and domain, which is not where the client should see it | Track it as the backlog task. Port the origin first; edge features follow the zone. |
| The edge secret leaks, or is reused across environments | A "bypass is impossible" claim is falsified mid-demo | Generate per environment, keep it in the operator's environment only, rotate by re-applying. Do not screen-share the Cloud Run environment variables. |
| Audience reads the header control as our production recommendation | Credibility damage in a security bid | State the production pattern explicitly in both the demo narrative and the RFP text. |
| GCP IAM propagation flakiness | Bootstrap fails intermittently | Carry over the `time_sleep` waits unchanged. They exist for exactly this reason. |
| ~~Cloudflare provider v5 renamed and restructured many resources relative to v4~~ | — | Retired. Modules are written for v5 and schema-validated against 5.28.1 with `tofu validate`. Runtime behaviour still unproven, since no zone exists. |
| Enterprise entitlement assumed but not verified on the actual zone | `0002` and `0006` specified against features we cannot use | Confirm the add-on is active on the demo zone, not just on the account, as part of task 2. |

## Test and demo strategy

| Acceptance criterion | How it is verified |
| --- | --- |
| Reachable via Cloudflare | `curl -sI https://<hostname>` returns 200 and the response carries `cf-ray` |
| Origin bypass refused | `curl -sI https://<cloud-run-url>` returns 403 |
| Sent versus arrived | Load generator counter against origin counter over the same window |
| Feature toggle | `tofu apply -target=module.<feature>` with `enable_<feature>` flipped; the plan shows no replacement of origin resources |
| Clean teardown | `gcloud run services list` and friends return empty; the inventory object exists in the bucket |

## Rollout notes

Stand-up order:

1. Confirm `pt-accenture.cftenant.com` is active on Cloudflare, which account
   holds it, and that the Bot Management add-on is live on that zone.
2. Reimplement the app and the GCP Terraform under `src/` as tracked files.
3. Add the GCP pre-flight to the wizard (task 6b); the rendering half is done.
4. Add the Cloudflare zone module and prove FR-5.
5. Add the transform rule and the origin-side header check; prove the bypass is refused.
6. Port the load generator; prove FR-8 and FR-9.
7. Full bootstrap, demo and teardown rehearsal on a throwaway project.
8. Port the origin to the Azure EBC tenant, then repeat 4–7 under
   `pt-accenture.cftenant.com`.

Demo notes:

- Show the client the target tenant and domain only. The personal lab is for
  building and rehearsal.
- When showing the bypass refused (S-3), say out loud that the shared-secret
  header is demo-grade, and name the production pattern.
