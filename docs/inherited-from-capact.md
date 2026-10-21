# Kickstart: what came from the CapAct MVP

This repository did not start from an empty directory. **MyCapAct** — an earlier
MVP built as the Cloud Security CoE's lab platform — was used to kickstart it.
Its first lab, "Cloudflare Bot Handling", already deployed the kind of web/API
application this RFP demo needs to put behind Cloudflare, with a working
environment lifecycle around it. A second generation, MyCapActV2, added a load
generator.

Both MVPs were copied in briefly as a reference and a starting point, then
removed once the useful parts had been read and recorded here. **They live in
separate projects outside this repository and are not a dependency.** Nothing in
this repository links to them, imports from them, or breaks if they move. This
page is the record of what their design contributed, so the reasoning is
available to anyone working here without having to go and find the originals.

Treat references to CapAct below as history, not as pointers to code you can
open. Where the MVP's code is to be reused, it is reimplemented under `src/` as
tracked files owned by this repository.

## Carried over unchanged

These are design decisions worth inheriting as they stand.

| Decision | Why it carries over |
| --- | --- |
| Two-script lifecycle: one to create an environment, one to destroy it | Disposable, reproducible, cheap environments — the same properties an RFP demo needs. |
| Epoch-suffixed environment names (`<name>-<unix-epoch>`) | Lets several demo environments exist in parallel without collisions. |
| Audit bucket created **outside** Terraform | Survives `destroy`, so evidence of what was built and torn down outlives the environment. Multiple environments share one bucket. |
| Log sink with an empty filter writing to GCS, writer granted only `roles/storage.objectCreator` | Captures everything, write-only. A good evidence trail for a security demo. |
| Confirm-by-typing-the-environment-name teardown guard | Cheap protection against destroying the wrong environment. |
| Pre-destruction resource inventory, uploaded under `previous-labs/<name>/` | Proves what existed at teardown time. |
| IAM pre-flight before Terraform runs, covering the submitter and the Compute default service account | Hard-won. Without it, submitting a Cloud Build with an explicit service account fails with `PERMISSION_DENIED`. |
| Explicit waits for service agents and IAM propagation | Also hard-won. Google provisions service agents asynchronously after API enablement, and the log sink writer binding fails without the wait. |
| Container builds through Cloud Build, triggered by a hash of the app sources | No local Docker needed, and images rebuild only when the application actually changes. |
| Cloud Run scale-to-zero, Firestore, Artifact Registry | Near-zero cost when idle. |
| OpenTofu over Terraform; `europe-west1` | Licensing (MPL 2.0) and proximity to the team in Portugal. The reasoning and the install recipe are preserved in [prerequisites.md](prerequisites.md). |

## Carried over with changes

| Subject | Change |
| --- | --- |
| The whiteboard application | Keep the shape as the demo origin. Its message endpoints give both a browser surface and a REST surface, which is what lets API Security and Bot Management be demonstrated against one service. |
| The bootstrap script | **Stop generating source from heredocs.** The MVP's script emitted the application and all Terraform from roughly 1100 lines of embedded heredocs — reasonable for a self-contained lab handed out as a single file, wrong here, where the repository itself is the deliverable. Sources become tracked files under `src/`; bootstrap renders only per-environment configuration. |
| Terraform layout | Split into a GCP module for the origin and one Cloudflare module per edge feature, so features can be enabled and demonstrated one at a time. |
| Environment metadata file | Gains the Cloudflare zone and hostname alongside the GCP fields. |
| Cloud Run ingress | The MVP left the origin open to the internet. That lets a visitor bypass the edge entirely and invalidates the whole demo — addressed by `0001` FR-7. |
| Notification email | Keep the idea; drop the hardcoded distribution lists and the manual URL substitution step. |

## From the second generation

| Subject | Use here |
| --- | --- |
| The `freeza-vegeta` load generator — Vegeta driven by a small control panel, with Prometheus and Alertmanager alongside | The traffic and bot simulator. Drives the Bot Management, Rate Limiting and DDoS demos, and its metrics supply the evidence: requests sent against requests that reached the origin. |
| Container build and Artifact Registry push workflow | The container workflow for the load generator. |

## Deliberately dropped

| Subject | Why |
| --- | --- |
| Multi-lab catalog framing, lab roadmap, AWS and Azure ambitions | CapAct was a CoE training product. This repository has one job: the Cloudflare RFP demo. |
| The Kubernetes and HPA autoscaling workstream | The origin here is Cloud Run. Horizontal pod autoscaling is out of scope. |
| Permissive CORS on every response | Acceptable in a training lab, bad optics in a security RFP demo. Revisit when API Security lands. |
