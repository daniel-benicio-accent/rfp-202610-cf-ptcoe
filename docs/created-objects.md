# Objects a demo creates

A checklist for walking the consoles after `tofu apply`, and for knowing what
is left behind after teardown.

Throughout, `<name>` is the demo name, `<project>` the GCP project and
`<region>` the region — the values in `demos/<name>/.envconfig`.

Most of this is automated:

```bash
./scripts/project-verify.sh <name>
```

Use the lists below when you want to see the objects yourself, or when
`project-verify.sh` reports a failure and you want to look closer.

## 1. Managed by Terraform

These are what `tofu apply` created, and what `./scripts/project-nuke.sh`
destroys. If one is missing, the apply did not finish.

### Cloud Run — console: Cloud Run → Services

- [ ] Service `<name>` exists, region `<region>`, green tick
- [ ] Latest revision is serving 100% of traffic
- [ ] Container image points at `<region>-docker.pkg.dev/<project>/<name>/<name>:<hash>`
- [ ] Container tab: `EDGE_SECRET` and `EDGE_SECRET_HEADER` are present under Variables
- [ ] Scaling is 0–2 instances, 1 vCPU, 512 MiB
- [ ] Security tab: service account is `<name>-sa@<project>.iam.gserviceaccount.com`
- [ ] Permissions: `allUsers` has `roles/run.invoker`

That last one looks alarming in a security demo and is deliberate: Cloudflare
has to be able to reach the service, and Cloud Run cannot filter by source IP.
The actual gate is the `EDGE_SECRET` header, checked by the application on
every request. See spec `0001` FR-7.

### Artifact Registry — console: Artifact Registry → Repositories

- [ ] Repository `<name>`, format Docker, region `<region>`
- [ ] One image `<name>` with a tag matching the hash on the Cloud Run revision

The tag is a hash of the application sources, so it only changes when the app
changes. Same tag on the registry and the revision means the running container
is the code in `demos/<name>/app/`.

### Firestore — console: Firestore → Data

- [ ] Default database exists, Native mode, location `<region>`
- [ ] After using the app once: collection `whiteboard`, document `current`,
      field `text`

The collection does not exist until the first message is written. An empty
Firestore right after apply is normal.

### IAM — console: IAM & Admin → IAM (tick "Include Google-provided role grants")

- [ ] Service account `<name>-sa@<project>.iam.gserviceaccount.com` exists
- [ ] It holds exactly these five project roles:
      `roles/datastore.user`, `roles/cloudbuild.builds.builder`,
      `roles/artifactregistry.writer`, `roles/logging.logWriter`,
      `roles/storage.objectAdmin`
- [ ] On the service account itself (IAM & Admin → Service Accounts → the SA →
      Permissions): your own account holds `roles/iam.serviceAccountUser` and
      `roles/iam.serviceAccountTokenCreator`

Those last two are resource-scoped on purpose. Without them `gcloud builds
submit --service-account=...` fails with `PERMISSION_DENIED`, even for a
project Owner.

### APIs — console: APIs & Services → Enabled APIs

- [ ] `run`, `firestore`, `artifactregistry`, `cloudbuild`, `storage`,
      `logging`, `iam`, `iamcredentials`

Expect to see many more than these eight. A GCP project enables a default set
of its own, and Terraform only adds what it needs. Extra entries are not a
problem; a missing one from the list above is.

### Logging — console: Logging → Log Router

- [ ] Sink `<name>-audit-sink`, destination the audit bucket, empty filter
- [ ] Its writer identity has `roles/storage.objectCreator` on that bucket

An empty filter is intentional: capture everything. The writer can append
evidence but cannot read or delete it.

## 2. Created outside Terraform, on purpose

- [ ] Bucket `gs://<audit-bucket>` — uniform access, public access prevented

It lives outside Terraform so it **survives `tofu destroy`** and keeps the
record of every demo that ever ran. Several demos share one bucket. The cost is
that nothing creates it as part of the apply, and the log sink then fails with
"Bucket does not exist" after everything else has been built.

`bootstrap-terraform.sh` now creates it during the pre-flight. For a demo made
before that existed:

```bash
gcloud storage buckets create gs://<audit-bucket> --project=<project> \
  --location=<region> --uniform-bucket-level-access --public-access-prevention
```

Then re-run `tofu apply` to create the sink.

## 3. Created on the side, and NOT destroyed

Nothing in this repository creates these — Google does, as a side effect — and
`tofu destroy` does not remove them. They are cheap, but they are real, so
check them if you are chasing stray cost.

- [ ] `gs://<project>_cloudbuild` — uploaded build sources, one object per build
- [ ] `gs://<project-number>-global-cloudbuild-logs` — build logs
- [ ] Google-managed service agents in IAM, created by API enablement

```bash
gcloud storage ls --project=<project>
```

Empty or delete the two Cloud Build buckets yourself when a project is retired.

## 4. Cloudflare

Only after the zone module is applied.

### Dashboard: DNS → Records

- [ ] A `CNAME` for `<subdomain>`, content the `*.run.app` hostname
- [ ] Proxy status is **Proxied** — the orange cloud. Grey means traffic skips
      Cloudflare entirely and every edge feature is bypassed.

### Dashboard: Rules → Overview

- [ ] An origin rule `origin-host-rewrite` overriding the Host header
- [ ] A transform rule `edge-secret-injection` setting the edge secret header

Both are required. Without the Host rewrite, Cloud Run answers 404 to
everything and it looks like broken DNS. Without the secret injection, the
origin answers 403 to everything.

### From a terminal

```bash
curl -sI https://<hostname>/ | grep -i cf-ray     # proof it went through the edge
curl -s  https://<hostname>/api/stats             # arrivals counter, through the edge
curl -sI https://<cloud-run-url>/                 # must be 403
```

- [ ] `cf-ray` header present
- [ ] Hostname returns 200
- [ ] Direct Cloud Run URL returns 403

### Per feature, as each one lands

- [ ] Security → WAF → Custom rules: one rule per enabled feature
- [ ] The rule is scoped to `<hostname>`, not the whole zone
- [ ] Security → Events shows the matched rule and action after a test request
