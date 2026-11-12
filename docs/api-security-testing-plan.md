# API security testing plan: discovery and schema validation

How the API Discovery and Schema Validation measurements for spec
[0006](../specs/0006-api-security/spec.md) were taken, and how to repeat them.
They ran against OWASP Juice Shop and a go-httpbin demo API, both behind
Cloudflare.

The RFP asks for six API security demonstrations, listed in the spec's Context,
and this plan covers two of them: API discovery and schema validation. mTLS is
in progress with Dinis and Micael and will be written up here. API-specific WAF
policies, API rate limiting and protection against anomalous traffic are still
to do. The [tasks](../specs/0006-api-security/tasks.md) track each one.

- **Feature spec:** [specs/0006-api-security/spec.md](../specs/0006-api-security/spec.md)
- **Traffic generator:** [scripts/apidiscovery-juiceshop-baseline-traffic.py](../scripts/apidiscovery-juiceshop-baseline-traffic.py)
- **Test harness:** [scripts/juiceshop_schema_validation_demo.sh](../scripts/juiceshop_schema_validation_demo.sh)
- **Schemas:** [demos/api-security-schemas-manifests/](../demos/api-security-schemas-manifests/)

Throughout, `$DEMO_HOST` is the proxied Juice Shop hostname (the `servers` URL
in the Juice Shop schema) and `$API_HOST` the go-httpbin hostname. Times are as
logged on the client, in WET (UTC+0).

## Contents

- [Status at a glance](#status-at-a-glance)
- [1. Prerequisites](#1-prerequisites)
- [2. API Discovery](#2-api-discovery)
- [3. Schema validation](#3-schema-validation)
- [4. Tracing a block with its Ray ID](#4-tracing-a-block-with-its-ray-id)
- [5. Evidence to keep per run](#5-evidence-to-keep-per-run)
- [6. Open items](#6-open-items)

## Status at a glance

| ID | Test | Covers | Tool | Expected | Last result |
| -- | ---- | ------ | ---- | -------- | ----------- |
| D-1 | Discovery fills the inventory from baseline traffic | S-1, FR-2 | traffic generator | Unsaved operations appear under **Discovered** | 21 new operations, first seen about 48 h after the traffic started (10 Nov 2026) |
| SV-1 | Schema validation, Juice Shop | S-2, FR-3 | harness, built-in cases | Off-schema requests get 403 at the edge; valid ones reach Juice Shop | 4/4 attacks blocked, 5/5 valid requests through (9 Nov 2026) |
| SV-2 | Schema validation, go-httpbin | S-2, FR-3 | harness, built-in cases | As SV-1 | 6/6 attacks blocked, 3/3 valid requests through (9–10 Nov 2026) |
| SV-3 | Fallthrough: request to an undeclared endpoint | FR-3 | harness, `FALLTHROUGH=on` | 403 at the edge | Not run |
| SV-4 | Schema on the mTLS partner route | S-3, FR-3, FR-4 | harness, client certificate | Valid slug reaches the origin, malformed slug gets 403 | Not run |
| AT-1 | Every block credited to the control that fired | FR-8 | Ray ID lookup | Each 403 traced to the rule under test | Pending. Three login cases were blocked before the schema existed ([note A](#note-a)) |

## 1. Prerequisites

These apply to both tests.

- **API Shield** must be active on the zone. It is a paid Enterprise add-on, and
  both Discovery and schema validation need it.
- **Use a client outside Cloudflare.** Discovery ignores traffic that comes from
  Workers. Run the scripts from a laptop or a VM; the runs below used WSL Ubuntu
  on a laptop. You need `python3` with `requests` for the generator, and `bash`,
  `curl` and `jq` for the harness. `python3-yaml` converts the schemas to JSON.
- **Keep edge rules out of the generator's way.** Discovery counts only
  requests that get a 2xx at the edge, so a rule that blocks or challenges the
  generator hides those operations. On 8 November the first `--check` runs
  failed 5 of 33 flows: the edge blocked `PUT` and `DELETE` on the host, and
  `POST /api/Complaints/` got a 429 challenge. The long run started only after
  `--check` passed all 33. The generator identifies itself with the user agent
  `juiceshop-baseline-generator/2.0`, which a WAF skip rule can match.
- **Turn the WAF managed rulesets off for schema validation runs.** That way a
  403 can only come from the control under test. Every run in section 3 had
  them off.

## 2. API Discovery

### 2.1 What Discovery counts

From Cloudflare's [Discovery](https://developers.cloudflare.com/api-shield/security/api-discovery/)
page (updated 29 Sep 2026), a request counts only if all of these hold:

- it gets a 2xx response from the Cloudflare edge;
- it does not come from a Cloudflare Worker;
- its endpoint gets at least 500 requests within a continuous 10-day period.

Discovery works on sampled traffic, and Cloudflare publishes no refresh interval.

### 2.2 Generate the baseline traffic

The generator behaves like the Juice Shop Angular front end. It runs 33 flows
covering 45 operations, as six synthetic users who register and log in, then
send `Authorization: Bearer <JWT>` on every call. Writes are round trips
(create, read, update, delete), so the shop's data does not grow. The two flows
that cannot clean up after themselves, sign-up and complaints, stop at
`--target`. The script's header describes the rest.

1. Install the dependency: `pip install requests`.
2. Run a preflight. It makes one pass over every flow, then exits:

   ```bash
   python3 scripts/apidiscovery-juiceshop-baseline-traffic.py --base-url https://$DEMO_HOST --check
   ```

   It must end with `Preflight: all 33 flows returned 2xx`. If Cloudflare
   blocks or challenges a flow, the output names the operation and gives a Ray
   ID. Find the rule behind it ([section 4](#4-tracing-a-block-with-its-ray-id))
   and fix it before you go on.
3. Start the long run in the background, logging to `scripts/baseline.log`
   (gitignored):

   ```bash
   nohup python3 scripts/apidiscovery-juiceshop-baseline-traffic.py \
       --base-url https://$DEMO_HOST --duration-hours 72 > scripts/baseline.log 2>&1 &
   ```

4. Every 5 minutes the log gets a report with one row per operation: its 2xx
   count against `--target`, and every other outcome.
   - `CF-CHALLENGE` and `CF-BLOCK-<status>` are edge mitigations.
   - `ERR` is a network error.
   - A bare status code is Juice Shop's own answer.
   - A footer gives the Ray ID of the last edge mitigation for each affected
     operation.

| Option | Default | 8 Nov run | Meaning |
| ------ | ------- | --------- | ------- |
| `--base-url` | required | `https://$DEMO_HOST` | Proxied Juice Shop URL |
| `--check` | off | run first | One pass over every flow, then exit |
| `--users` | 6 | 6 | Synthetic logged-in users |
| `--workers` | 6 | 6 | Concurrent workers |
| `--rps` | 3 | 3 | Average requests per second across all workers |
| `--target` | 1000 | 1000 | 2xx responses wanted per operation; Discovery needs 500, the margin covers sampling |
| `--login-interval` | 20 | 20 | Minimum seconds between logins, to stay under login rate limits |
| `--duration-hours` | 72 | 72 | Run length |
| `--report-minutes` | 5 | 5 | Report interval |
| `--user-agent` | `juiceshop-baseline-generator/2.0` | default | User agent for every request |
| `--verbose` | off | off | Log every non-2xx response with the start of its body |

### 2.3 Run record: 8–9 November 2026

| Item | Value |
| ---- | ----- |
| Start | 8 Nov 2026 12:54, after a clean preflight (all 33 flows 2xx) |
| End | The log stops at 9 Nov 2026 16:00, after 27 h 05 min of the 72 h requested |
| Requests | 99,997, averaging about 1.0 req/s against the 3 requested; Juice Shop is CPU-bound on some endpoints |
| Coverage | 44 of 45 operations passed 1,000 2xx. `POST /api/SecurityAnswers/` stopped at 978 along with the sign-up flow. All 45 cleared Discovery's 500 |
| Edge mitigations | Up to 14 `CF-CHALLENGE` per operation over the whole run |
| Other noise | Network errors (`ERR`), up to 777 on `POST /api/Feedbacks/`; 338 Juice Shop 500s on `POST /api/BasketItems/` |

### 2.4 Reading the result

In the dashboard, open the zone, then **Security** > **Web assets** >
**Operations**, and select the **Discovered** quick filter. It shows
operations in the candidate and shadow states.

- **Latency.** Unsaved operations were first seen **about 48 hours after the
  generator started**, on 10 November 2026, some 21 hours after it stopped.
  Leave at least three days between starting the generator and the demo.
- **What appeared.** The export taken afterwards lists 26 operations. A sample
  is committed as
  [scripts/sample-api-endpoints-…-thresholds.json](../scripts/sample-api-endpoints-9ca4e3dca07b60a9867dc56f2953f63c-app-pt-cybersec-coe-juiceshop.pt-accenture.cftenant.com-thresholds.json):

  | Source | Count | Operations |
  | ------ | ----- | ---------- |
  | Saved by the Juice Shop schema upload (9 Nov) | 5 | `GET /api/Products/{var1}`, `GET /rest/products/search`, `POST /api/BasketItems/`, `POST /api/Feedbacks/`, `POST /rest/user/login` |
  | Discovered from the generator's traffic | 20 | `GET /api/Addresss`, `GET /api/Cards`, `POST /api/Cards/`, `DELETE /api/Cards/{var1}`, `DELETE /api/BasketItems/{var1}`, `GET /api/Challenges/`, `POST /api/Complaints/`, `GET /api/Deliverys`, `GET /api/Feedbacks/`, `GET /api/Quantitys/`, `GET /api/SecurityQuestions/`, `POST /api/Users/`, `GET /rest/2fa/status`, `GET /rest/admin/application-configuration`, `GET /rest/admin/application-version`, `GET /rest/basket/{var1}`, `GET /rest/captcha/`, `GET /rest/continue-code`, `GET /rest/languages`, `GET /rest/user/security-question` |
  | Discovered from browser traffic | 1 | `GET /socket.io/`: the generator never calls it, so it came from the Juice Shop front end |

- **Naming.** Discovery names path variables `{var1}`, `{var2}` and so on, so
  `/api/Products/{id}` in the schema is `/api/Products/{var1}` in the inventory.
- **Missing from the export.** 20 of the generator's operations are not in the
  export, although each got at least 978 2xx responses:
  - `/api/Addresss`: `POST /api/Addresss/`, and `GET`, `PUT` and `DELETE` on
    `/api/Addresss/{id}`.
  - Other `/api/` resources: `GET` and `PUT /api/BasketItems/{id}`,
    `GET /api/Cards/{id}`, `GET /api/Deliverys/{id}`,
    `DELETE /api/Feedbacks/{id}`, `POST /api/SecurityAnswers/`,
    `GET /api/Users/{id}`.
  - `/rest/`: `GET /rest/deluxe-membership`, `GET /rest/memories/`,
    `GET /rest/order-history`, `PATCH /rest/products/reviews`,
    `GET /rest/products/{id}/reviews`, `GET /rest/track-order/{id}`,
    `GET /rest/user/whoami`, and `GET` and `PUT /rest/wallet/balance`.

  The record does not show whether they were still pending in Discovery or
  were simply not saved. Next time, count the **Discovered** filter before
  saving anything.

### 2.5 Repeat checklist

1. Check the prerequisites in [section 1](#1-prerequisites).
2. Run `--check` until all 33 flows return 2xx.
3. Start the long run at least three days before you need the result.
4. Keep `scripts/baseline.log`. Its last report is the traffic evidence.
5. From about 48 h after the start, check **Discovered** once a day. When the
   first operations appear, note the date and count, and take a screenshot.
6. Export the operations as OpenAPI JSON, for the record and for schema-mode
   runs ([section 3.3](#33-the-test-harness)).

## 3. Schema validation

### 3.1 The schemas

| File | Host | Endpoints | What it constrains |
| ---- | ---- | --------- | ------------------ |
| [1-juiceshop-schema-validation.yaml](../demos/api-security-schemas-manifests/1-juiceshop-schema-validation.yaml) | `$DEMO_HOST` | 5 | <ul><li>Login body: email format, both fields required</li><li>Search `q`: safe characters only, at most 50</li><li>Product `id`: integer ≥ 1</li><li>Basket body: `quantity` 1–10</li><li>Feedback body: `rating` 1–5</li></ul> |
| [2-httpbin-api.yaml](../demos/api-security-schemas-manifests/2-httpbin-api.yaml) | `$API_HOST` | 4 | <ul><li>`page`: integer 1–100</li><li>Order body: SKU format `AAA-0000`, `quantity` 1–100, no undeclared fields</li><li>Order `id`: integer ≥ 1</li><li>Partner slug: must match a pattern; the route also requires mTLS</li></ul> |

Each Juice Shop constraint matches an abuse case that WAF signatures miss:
negative quantity, zero-star feedback, type confusion, and injection through
free-text fields. The schema's description lists them.

> **Check before uploading:** the committed `2-httpbin-api.yaml` names the
> Juice Shop host under `servers`. Cloudflare takes an operation's hostname
> from that entry, so change it to `$API_HOST` first.

### 3.2 Load and enforce the schema

The steps follow Cloudflare's [Schema validation](https://developers.cloudflare.com/api-shield/security/schema-validation/)
page (updated 5 Oct 2026).

1. **Upload the schema.** Go to **Security** > **Web assets** > **Schema
   validation** > **Add validation**. Choose the YAML file, then select **Add
   schema and endpoints**. A dashboard upload also saves the schema's operations
   to the inventory. Changes can take several minutes to apply.
2. **Enforce it.** An uploaded schema only detects violations. To block them,
   add a WAF custom rule on `cf.schema_validation.uploaded.violated`, scoped to
   the host:

   ```txt
   cf.schema_validation.uploaded.violated and http.host eq "<demo-host>"
   ```

   Cloudflare's [enforcement guide](https://developers.cloudflare.com/waf/detections/application-profiles/enforce-profiles-with-custom-rules/)
   recommends running the rule with Log first, then switching it to Block.
   Record the rule's name and action with the results: nobody wrote down which
   rule was used on 9 November.
3. **Fallthrough rule** (optional; needed for SV-3). In **Security rules** >
   **Templates**, use *Mitigate API requests to unidentified endpoints*.
   Alternatively, write a custom rule on `cf.api_gateway.fallthrough_detected`.
   Scope it to `/api/` and `/rest/`, or it also blocks the Juice Shop front end.
   Requests to operations that are still candidates in Discovery also match it.
4. **Back to "without".** Delete the schema under **Schema validation** >
   **Schema settings** > **Active schemas**. Evaluation stops, but the
   operations stay in the inventory.

### 3.3 The test harness

`scripts/juiceshop_schema_validation_demo.sh` sends each case once with curl and
prints one row per case. It exits non-zero when any case misses its expected
outcome. Configure it with environment variables and an optional schema file:

| Parameter | Default | Effect |
| --------- | ------- | ------ |
| `BASE_URL` | Required in built-in mode | Juice Shop URL. In schema mode it falls back to the schema's `servers[0].url` |
| `API_BASE_URL` | Unset | go-httpbin URL. If unset, the httpbin cases are skipped. Built-in mode only |
| `API_CLIENT_CERT`, `API_CLIENT_KEY` | Unset | PEM client certificate and key. Built-in mode sends them only to the mTLS partner route; schema mode sends them with every request |
| `SKIP_MTLS` | `off` | `on` skips the partner cases, and stops schema mode sending the certificate, even when one is set |
| `FALLTHROUGH` | `off` | `on` runs the undeclared-endpoint case. It needs the fallthrough rule. Built-in mode only |
| First argument | None | An OpenAPI 3.0 **JSON** file. The harness then runs schema mode instead of the built-in cases |

**Reading the output.** Each row has `CASE`, `EXPECTED`, `HTTP`, `RESULT` and
`CF-RAY`.

- `edge-block` means a 403 whose body names Cloudflare or reads
  `error code: NNNN`, the plain-text block page that curl receives.
- `origin` means any other response. That includes Juice Shop's own 401, 404
  and 500, which are expected with no session, the wrong test credentials or
  the wrong captcha. The request still got past the edge.
- `RESULT` is `PASS` when the outcome matches `EXPECTED`, and
  `FAIL(<actual>)` otherwise.
- `EXPECTED` is always the outcome with the schema enforced. A run without the
  schema shows the attacks as `FAIL(origin)` and exits non-zero; that is the
  "before" evidence.

A 403 shows only that Cloudflare stopped the request, not which control did.
[Section 4](#4-tracing-a-block-with-its-ray-id) covers that.

**Built-in cases.** There are 15 on Juice Shop:

- four login cases;
- two each for product, search, basket and feedback;
- two front-end calls with nothing to validate, `/rest/captcha/` and the
  socket.io handshake, which must keep working;
- the undeclared endpoint.

There are 11 on go-httpbin: three for `page`, four for orders, two for order id
and two for the partner route. These are the cases on the demo slides.

```bash
# Once without the schema (before the upload, or after deleting it), then again with it enforced.
BASE_URL=https://$DEMO_HOST API_BASE_URL=https://$API_HOST \
  ./scripts/juiceshop_schema_validation_demo.sh | tee scripts/schema-validation-check.log

# Add the mTLS partner route (SV-4).
API_CLIENT_CERT=client.pem API_CLIENT_KEY=client.key \
BASE_URL=https://$DEMO_HOST API_BASE_URL=https://$API_HOST \
  ./scripts/juiceshop_schema_validation_demo.sh

# Leave the partner route out even with a certificate set, and add the fallthrough case (SV-3).
SKIP_MTLS=on FALLTHROUGH=on BASE_URL=https://$DEMO_HOST API_BASE_URL=https://$API_HOST \
  ./scripts/juiceshop_schema_validation_demo.sh
```

`scripts/schema-validation-check.log` is gitignored, and each run overwrites
it. Copy each run to a dated file if you want to keep it.

**Schema mode.** Pass an OpenAPI JSON file, and the harness builds its cases
from that file instead. It sends one compliant request per operation, built
from the schema's examples, defaults and constraints. It then sends one
violation for each constraint it can break:

- the wrong type: a number or boolean, or a string in a body field;
- `minimum`, `maximum`, `pattern`, `enum` or `maxLength`;
- a missing required query parameter or body field;
- an undeclared field where `additionalProperties` is `false`.

It covers path and query parameters and top-level JSON body fields, skips
`HEAD`, and needs `jq`. Convert the YAML files first:

```bash
for f in 1-juiceshop-schema-validation 2-httpbin-api; do
  python3 -c 'import json,sys,yaml; json.dump(yaml.safe_load(open(sys.argv[1])), sys.stdout, indent=2)' \
    "demos/api-security-schemas-manifests/$f.yaml" > "/tmp/$f.json"
done
./scripts/juiceshop_schema_validation_demo.sh /tmp/1-juiceshop-schema-validation.json
BASE_URL=https://$API_HOST ./scripts/juiceshop_schema_validation_demo.sh /tmp/2-httpbin-api.json
```

- **Dry runs only so far.** With a stubbed `curl` on 11 November 2026, the
  Juice Shop schema gave 41 cases (5 operations) and go-httpbin 20 (4
  operations). Neither has been run against the zone.
- **An export from Web assets** types every variable as a plain string, so it
  yields compliant requests only: one per operation, 26 for the sample
  export. That makes it a smoke test that the inventory's operations still
  reach the origin.
- **These are real requests.** From the export, `POST /api/Users/` with no body
  creates an empty Juice Shop account.

### 3.4 Run record: 9–10 November 2026

The same built-in cases ran without and with the schema, with the WAF managed
rulesets off both times. The Juice Shop run without the schema came before the
upload on 9 November; the go-httpbin one came after the run with the schema.
The results with the schema held across several runs. Ray IDs are given without
their data-centre suffix.

**SV-1, Juice Shop:**

| Case | Without schema | With schema |
| ---- | -------------- | ----------- |
| login: valid payload | 401 origin | 401 origin |
| login: email is a number · missing password · SQLi in email | 403 edge | 403 edge, but not credited to the schema ([note A](#note-a)) |
| product: numeric id | 200 origin | 200 origin |
| product: non-numeric id | 404 origin `a57e0d99189f41f6` | **403 edge** `a583aaf05c4b6923` |
| search: plain term | 200 origin | 200 origin |
| search: UNION-based SQLi | 500 origin `a57e0da21c4450de` | **403 edge** `a583aaf97f93e3bc` |
| basket: quantity 1 | 401 origin | 401 origin |
| basket: negative quantity | 401 origin `a57e0db4290662e8` | **403 edge** `a583ab011a2ee3c5` |
| feedback: rating 5 | 401 origin | 401 origin |
| feedback: rating 0 | 401 origin `a57e0db7cf7b0665` | **403 edge** `a583ab09981f1df8` |
| captcha: fetch · socket.io handshake | Not run | 200 origin |
| undeclared endpoint | Skipped | Skipped (`FALLTHROUGH` off) |

**SV-2, go-httpbin.** `/anything/*` answers 200 to anything, so every non-200
comes from Cloudflare.

| Case | Without schema | With schema |
| ---- | -------------- | ----------- |
| page 1 | 200 `a58449cf8c85c640` | 200 `a583ab190a556936` |
| page out of range (`500`) | 200 `a58449d87ef9cc1e` | **403** `a583ab220e3ff437` |
| page not a number (`abc`) | 200 `a58449d9dbb223a2` | **403** `a583ab23081ac1b1` |
| order: valid | 200 `a58449e028dce3c3` | 200 `a583ab240b2ec640` |
| order: negative quantity | 200 `a58449e77cccb59b` | **403** `a583ab25dcc5e3cd` |
| order: malformed SKU | 200 `a58449ee9a6fab0d` | **403** `a583ab26c8173b29` |
| order: undeclared field (`unit_price`) | 200 `a58449f63d94eeea` | **403** `a583ab2759d17072` |
| order id 42 | 200 `a58449ff3c2df437` | 200 `a583ab27f885df91` |
| order id `abc` | 200 `a5844a06c861692c` | **403** `a583ab2bfd904266` |
| partner: valid / malformed slug | Skipped (no certificate) | Skipped (no certificate) |

<a id="note-a"></a>**Note A: malformed logins.** The three malformed login
requests were blocked before the schema existed, so another control on the zone
blocks them. That control has not been identified yet, and their Ray IDs were
not recorded. Until a Ray ID lookup names the control, they are not evidence
for schema validation.

### 3.5 Repeat checklist

1. Turn the WAF managed rulesets off, and make sure no schema is active for the
   host. Delete it if there is one.
2. Run the harness and save the output. This is the "without" evidence.
3. Upload the schema and add the enforcement rule. Run it with Log first,
   check Security Events, then switch it to Block.
4. Wait a few minutes, then run the harness again. This is the "with" evidence.
   Every row should be `PASS` or `SKIP`.
5. Look up the Ray ID of every `edge-block` row
   ([section 4](#4-tracing-a-block-with-its-ray-id)) and record the rule that
   fired. A block from anything other than the enforcement rule is not
   evidence for schema validation.
6. Optional: set `FALLTHROUGH=on` once the fallthrough rule is in place (SV-3),
   and supply a client certificate for the partner route (SV-4).
7. Roll back by deleting the schema, or by switching the enforcement rule back
   to Log.

## 4. Tracing a block with its Ray ID

Cloudflare gives every request it handles a
[Ray ID](https://developers.cloudflare.com/fundamentals/reference/cloudflare-ray-id/)
and returns it in the `cf-ray` response header. In `a583aaf05c4b6923-MAD`, the
part after the dash is the data centre that served the request. Both scripts
print Ray IDs. The harness puts one in its `CF-RAY` column. The generator lists
one in its report footer for each operation the edge mitigated.

**In the dashboard** (see [Security Events](https://developers.cloudflare.com/waf/analytics/security-events/)):

1. Open the zone, then **Security** > **Analytics** > **Events**.
2. Set the time range to cover the run. Events are kept for 31 days, so the 9
   November Ray IDs expire around 10 December 2026.
3. Select **Add filter**, then **Ray ID** equals the ID. Leave off the suffix
   and the quotes.
4. Expand the event. It shows the action taken and the security feature that
   applied it, together with the rule. **Export event JSON** saves the raw
   values for the evidence folder.

**Reading it:**

| The event shows | What blocked the request |
| --------------- | ------------------------ |
| Custom rules, with a rule on `cf.schema_validation.uploaded.violated` | Schema validation, through its enforcement rule |
| Custom rules, with a rule on `cf.api_gateway.fallthrough_detected` | The fallthrough rule: no saved operation matched |
| Custom rules, with a rule on `cf.tls_client_auth.cert_verified` | mTLS |
| Managed rules | The WAF managed rulesets (spec [0004](../specs/0004-waf/spec.md)). They should be off for these runs |
| Rate limiting rules | A rate limiting rule |
| A bot or challenge feature, such as Bot Fight Mode or Security Level | Bot defences (spec [0002](../specs/0002-bot-management/spec.md)) |

Cloudflare's documentation gives the service names only as examples, so match
on the rule as well as the service.

- **Several events for one Ray ID** can happen, for example when a Log rule and
  a Block rule both match. The event with the Block action is the one that
  stopped the request.
- **No event** means no security product acted on the request, so the response
  came from the origin, whatever its status. Security Analytics shows every
  request, including those nothing acted on.
- **An event from a different control** than the one under test means that row
  is not evidence for the control. [Note A](#note-a) is the open case.

**From the command line.** The same events are in the GraphQL Analytics API,
dataset `firewallEventsAdaptive`. The query below has not been run from this
repository yet. If a field is rejected, list the dataset's fields with
introspection. The API token needs zone Analytics read access.

```bash
curl -s https://api.cloudflare.com/client/v4/graphql \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H 'Content-Type: application/json' \
  --data @- <<'EOF'
{"query": "query ($zone: String!, $ray: String!, $from: Time!, $to: Time!) { viewer { zones(filter: {zoneTag: $zone}) { firewallEventsAdaptive(filter: {rayName: $ray, datetime_geq: $from, datetime_leq: $to}, limit: 10) { datetime action source ruleId description clientRequestHTTPMethodName clientRequestPath } } } }",
 "variables": {"zone": "<zone-id>", "ray": "a583aaf05c4b6923", "from": "2026-11-09T00:00:00Z", "to": "2026-11-10T23:59:59Z"}}
EOF
```

In the result, `source` names the service and `ruleId` the rule. Look the rule
up under **Security rules**.

**Ray IDs to look up before they expire** (around 10 December 2026):

- `a583aaf05c4b6923`: the product request with a non-numeric id, sent with the
  schema in place. Expected result: the schema enforcement rule.
- `a57df0fc7915e3d1` (`POST /rest/user/login`) and `a57dfb4a980bfe4e`
  (`GET /rest/products/{id}/reviews`): the last edge mitigations in the
  generator's report on 9 November. They show what challenged the baseline
  traffic.
- The three malformed logins ([note A](#note-a)): their Ray IDs were not
  recorded. Run the cases again and look up the new ones.

## 5. Evidence to keep per run

- The generator's last report, from `scripts/baseline.log` (gitignored).
- A dated screenshot of **Discovered**, with the count of the first operations
  seen.
- The operations export, as OpenAPI JSON.
- The harness output for each run, labelled with or without the schema. It goes
  to `scripts/schema-validation-check.log` (gitignored); copy each run to a
  dated file.
- The event JSON from Security Events for every `edge-block` row.
- The enforcement rule's name, expression and action as they were during the
  run.

## 6. Open items

- **Note A:** find the control that blocks the malformed logins.
- **The 9 November enforcement rule** was never recorded.
- **20 of the generator's operations** are missing from the export
  ([section 2.4](#24-reading-the-result)).
- **SV-3 and SV-4** have not been run.
- **Schema mode** has not been run against the zone with the two committed
  schemas.
- **`2-httpbin-api.yaml`** names the wrong host under `servers`.
- **Infrastructure as code:** everything above was configured in the
  dashboard, but spec FR-1 asks for Terraform.
