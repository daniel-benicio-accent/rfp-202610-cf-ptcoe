# 0001 — Platform foundation — Tasks

| Field   | Value |
| ------- | ----- |
| Updated | 2026-11-12 |

The foundation is delivered on the target domain by João Grilo (task 14). The
documents stay `Draft`. The tasks below track the repository's own templates
and scripts, and the parts of the delivered foundation that are not yet in
Terraform/OpenTofu.

| # | Task | Covers | Status |
| - | ---- | ------ | ------ |
| 1 | Confirm the demo domain and that it is delegated to Cloudflare | FR-5 | done — `pt-accenture.cftenant.com`, proxied through Cloudflare, recorded 2026-11-12 |
| 2 | Verify the Bot Management add-on is active on that specific zone, not just the account | FR-6 | todo — API Shield is confirmed on the zone by `0006`; Bot Management not checked yet |
| 3 | ~~Decide the FR-7 origin-lockdown option~~ | FR-7 | done — shared-secret header, 2026-10-21 |
| 4 | Reimplement the origin app under `src/app/` as tracked files | FR-3, FR-4 | done — Flask UI plus REST API, 2026-10-21 |
| 5 | Write the GCP Terraform as a template, keeping the `time_sleep` waits | FR-3 | done — `src/terraform/_templates/gcp/`, schema-validated |
| 6a | Wizard rendering a complete demo into `demos/<name>/` with tfvars and `.envconfig` | FR-1, FR-3 | done — `scripts/bootstrap-terraform.sh` |
| 6b | GCP pre-flight in the wizard: audit bucket | FR-2, FR-12 | done — `--preflight`, or prompted when interactive |
| 6c | GCP pre-flight: optional project creation, submitter and Compute SA role grants | FR-2 | todo — not needed for a project Owner, so untested; a non-owner account will need it |
| 7 | Teardown with inventory, audit upload, typed confirmation and ordered destroy | FR-10, FR-11, FR-12 | done — `scripts/project-nuke.sh`; cloud calls not yet exercised |
| 8 | Zone template with the proxied record and TLS mode | FR-5 | part — record, Host rewrite and secret injection written; TLS mode still TODO |
| 9 | Add the edge transform rule injecting the secret header, and the origin-side check that 403s without it | FR-7 | origin half **verified on Cloud Run** (direct 403, header 200); edge half still unproven, no zone applied |
| 9b | Generate the edge secret per environment in `bootstrap.sh`; never write it to a tracked file | FR-7, NFR-3 | todo |
| 10 | Add the request counter to the origin app | FR-9 | done and **verified live** — `/api/stats` counted 1 arrival and correctly excluded refused requests, `/health` and itself |
| 11 | Port the Vegeta load generator to `src/load-generator/` | FR-8 | todo |
| 12 | Establish the `enable_<feature>` toggle pattern with one no-op module | FR-6 | done — `scripts/bootstrap-terraform.sh` bakes it into every generated module |
| 13 | End-to-end rehearsal: bootstrap, verify, teardown on a throwaway project | all | part — bootstrap and verify done on `rfp-202610-cfdemo`; teardown not yet exercised against live resources |
| 14 | Deliver the foundation on the target domain | FR-5 | done — João Grilo; the domain is proxied, and the architecture looks sound on review. Recorded 2026-11-12 |
| 15 | Write the delivered architecture into `plan.md`, and bring the parts built outside Terraform/OpenTofu under the templates | FR-3, NFR-4 | todo — with João Grilo |

## Definition of done

- [ ] Every acceptance criterion in `spec.md` passes.
- [ ] Code lives under `src/` and runs from a clean checkout.
- [ ] Component listed in its spec's row of `specs/README.md`.
- [ ] `specs/README.md` status updated.
- [ ] If AI usage is not `None`, `.gitignore` reviewed.
