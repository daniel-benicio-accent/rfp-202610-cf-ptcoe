# 0001 — Platform foundation — Tasks

| Field   | Value |
| ------- | ----- |
| Updated | 2026-10-21 |

Blocked on `spec.md` reaching `Approved`. Task 1 gates the whole backlog, not
just this spec.

| # | Task | Covers | Status |
| - | ---- | ------ | ------ |
| 1 | Confirm the demo domain and that it is delegated to Cloudflare | FR-5 | blocked |
| 2 | Verify the Bot Management add-on is active on that specific zone, not just the account | FR-6 | blocked on 1 |
| 3 | ~~Decide the FR-7 origin-lockdown option~~ | FR-7 | done — shared-secret header, 2026-10-21 |
| 4 | Reimplement the origin app under `src/app/` as tracked files | FR-3, FR-4 | todo |
| 5 | Write the GCP Terraform as a template, keeping the `time_sleep` waits | FR-3 | done — `src/terraform/_templates/gcp/`, schema-validated |
| 6a | Wizard rendering a complete demo into `demos/<name>/` with tfvars and `.envconfig` | FR-1, FR-3 | done — `scripts/bootstrap-terraform.sh` |
| 6b | Add the GCP pre-flight to the wizard: optional project creation, audit bucket, submitter and Compute SA role grants | FR-2 | todo |
| 7 | Teardown with inventory, audit upload, typed confirmation and ordered destroy | FR-10, FR-11, FR-12 | done — `scripts/project-nuke.sh`; cloud calls not yet exercised |
| 8 | Zone template with the proxied record and TLS mode | FR-5 | part — record, Host rewrite and secret injection written; TLS mode still TODO |
| 9 | Add the edge transform rule injecting the secret header, and the origin-side check that 403s without it | FR-7 | todo |
| 9b | Generate the edge secret per environment in `bootstrap.sh`; never write it to a tracked file | FR-7, NFR-3 | todo |
| 10 | Add the request counter to the origin app | FR-9 | todo |
| 11 | Port the Vegeta load generator to `src/load-generator/` | FR-8 | todo |
| 12 | Establish the `enable_<feature>` toggle pattern with one no-op module | FR-6 | done — `scripts/bootstrap-terraform.sh` bakes it into every generated module |
| 13 | End-to-end rehearsal: bootstrap, verify, teardown on a throwaway project | all | todo |

## Definition of done

- [ ] Every acceptance criterion in `spec.md` passes.
- [ ] Code lives under `src/` and runs from a clean checkout.
- [ ] Root `README.md` component index updated.
- [ ] `specs/README.md` status updated.
- [ ] If AI usage is not `None`, `.gitignore` reviewed.
