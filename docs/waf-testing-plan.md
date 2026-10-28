# Cloudflare WAF security testing plan

Formal test cases for validating the Cloudflare Web Application Firewall (WAF)
deployment, mapped to the OWASP Top 10:2025, exercised against the
[OWASP Juice Shop](https://owasp.org/www-project-juice-shop/) demo. Adapted from
the shared *Cloudflare WAF Testing Plan* document (v9) into the repository so it
can be maintained alongside the code it validates.

- **Feature spec:** [specs/0004-waf/spec.md](../specs/0004-waf/spec.md)
- **Runbook (how to stand the demo up and switch the WAF on/off):** [docs/wafdemo-owasp-juice-shop.md](wafdemo-owasp-juice-shop.md)
- **Executable tests:** the `pt-cybersecurity-coe` Bruno collection (requests `1.1`, `1.2`, `1.3`).

Throughout, `$DEMO_HOST` is the proxied demo hostname; the real value is never
written into the repository (see [conventions](conventions.md#personal-identifiers)).

> **Note:** the struck-through tests below (**1.4–1.12**) were **deprioritized**
> at the RFP scope meeting on 26 October 2026. Tests **1.1–1.3** cover the
> requirements defined in the solution deck; the remaining OWASP Top 10:2025
> cases are left to the delivery team's discretion to pursue full coverage, and
> are not part of the committed demo scope.

## Status at a glance

| # | Test | OWASP 2025 | Endpoint | Cloudflare control | Expected (WAF on) | Scope |
| - | ---- | ---------- | -------- | ------------------ | ----------------- | ----- |
| 1.1 | SQL Injection | Injection | `POST /rest/user/login` | OWASP Core Ruleset | Blocked (403) | **Committed** |
| 1.2 | Cross-Site Scripting | Injection | `GET /rest/products/search` | Managed Rules — XSS | Blocked (403) | **Committed** |
| 1.3 | Path / Directory Traversal | Broken Access Control | `GET /ftp` | Managed Rules — LFI | Blocked (403) | **Committed** |
| ~~1.4~~ | ~~Broken Access Control (A01)~~ | ~~A01:2025~~ | ~~`GET /rest/admin/application-configuration`~~ | ~~Core Ruleset (forced browsing)~~ | ~~Blocked / challenged~~ | ~~Deprioritized~~ |
| ~~1.5~~ | ~~Security Misconfiguration (A02)~~ | ~~A02:2025~~ | ~~`GET /.env`, `GET /server.js`~~ | ~~Exposed credentials / bad extensions~~ | ~~Blocked (403)~~ | ~~Deprioritized~~ |
| ~~1.6~~ | ~~Software Supply Chain (A03)~~ | ~~A03:2025~~ | ~~`GET /api/dependencies`~~ | ~~Core Ruleset / virtual patching~~ | ~~Blocked (403)~~ | ~~Deprioritized~~ |
| ~~1.7~~ | ~~Cryptographic Failures (A04)~~ | ~~A04:2025~~ | ~~`POST /rest/user/login` over HTTP~~ | ~~Always Use HTTPS / HSTS~~ | ~~Redirected (301/308)~~ | ~~Deprioritized~~ |
| ~~1.8~~ | ~~Insecure Design (A06)~~ | ~~A06:2025~~ | ~~`POST /api/users/forgot-password`~~ | ~~Rate limiting / bot management~~ | ~~Rate-limited / challenged~~ | ~~Deprioritized~~ |
| ~~1.9~~ | ~~Authentication Failures (A07)~~ | ~~A07:2025~~ | ~~`POST /rest/user/login` (loop)~~ | ~~Rate limiting — brute force~~ | ~~Challenged → 429/403~~ | ~~Deprioritized~~ |
| ~~1.10~~ | ~~Software/Data Integrity (A08)~~ | ~~A08:2025~~ | ~~`POST /b2b/v2/orders`~~ | ~~Core Ruleset (deserialization)~~ | ~~Blocked (403)~~ | ~~Deprioritized~~ |
| ~~1.11~~ | ~~Logging & Alerting Failures (A09)~~ | ~~A09:2025~~ | ~~any blocked endpoint~~ | ~~Security Analytics / Logpush~~ | ~~Event logged, no payload leak~~ | ~~Deprioritized~~ |
| ~~1.12~~ | ~~Exceptional Conditions (A10)~~ | ~~A10:2025~~ | ~~`GET /api/Challenges` (malformed)~~ | ~~Managed / custom rules~~ | ~~Handled, no stack trace~~ | ~~Deprioritized~~ |

Architecture points **2.1** and **2.2** below remain in scope — they are
deployment properties of the demo, not OWASP extension tests.

## 1. Committed tests

Each test is run twice: once with the WAF **off** to capture the vulnerable
baseline, then with it **on** to show the edge refusing the same request. A WAF
block is a **403** carrying a `cf-ray` header and a Cloudflare block page; it
never reaches the origin, and it appears in **Security → Events** filtered by
host. An application error (for example a `401` from Juice Shop's own login) is
*not* a WAF block — it means the request passed the edge and the origin answered.

### 1.1. SQL Injection (SQLi)

- **Business value:** prevents account compromise and unauthorized data access.
- **Endpoint:** `POST /rest/user/login`
- **Cloudflare control:** Cloudflare OWASP Core Ruleset.
- **Bruno request:** `1.1. SQL Injection (SQLi) - Primary Test`.
- **Payload (JSON body):**

  ```json
  { "email": "' OR 1=1 --", "password": "anything" }
  ```

- **Baseline (WAF off):** the login bypass succeeds — `200 OK` with an
  authentication token for `admin@juice-sh.op`. This is the point of the
  baseline: the application is genuinely vulnerable, so the block afterwards is
  meaningful.
- **Expected (WAF on):** **blocked (403)** with a `cf-ray`; the request never
  reaches the origin. Security Events attributes it to the **Cloudflare OWASP
  Core Ruleset** with the anomaly score reached.
- **Note:** the body must actually be sent as JSON. A request with no body
  returns the origin's generic `401 "Invalid email or password."`, which is an
  application response, not a WAF block — confirm the body is present before
  reading anything into the result.

### 1.2. Cross-Site Scripting (XSS)

- **Business value:** prevents session hijacking and browser-based attacks.
- **Endpoint:** `GET /rest/products/search`
- **Cloudflare control:** Managed Rules — XSS Protection (the `xss`-tagged rules
  of the Cloudflare Managed Ruleset).
- **Bruno request:** `1.2. Cross-Site Scripting (XSS) - Primary Test`.
- **Payload (query parameter):** `q=<script>alert(1)</script>`
- **Baseline (WAF off):** `200 OK`; the request reaches the search endpoint.
- **Expected (WAF on):** **blocked (403)** with a `cf-ray`; Security Events
  attributes it to the Cloudflare Managed Ruleset XSS rule.

### 1.3. Path / Directory Traversal

- **Business value:** prevents unauthorized file and system access.
- **Endpoint:** `GET /ftp`
- **Cloudflare control:** Managed Rules — LFI Protection (the `lfi`-tagged rules
  of the Cloudflare Managed Ruleset).
- **Bruno request:** `1.3. Path - Directory Traversal - Primary Test`.
- **Payload (URL path):** `/ftp/../../../../etc/passwd`
- **Baseline (WAF off):** reaches the origin (`200`). To make the baseline
  actually return file contents rather than the SPA index, use **URL-encoded**
  traversal (`/ftp/%2e%2e%2f%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd`): HTTP
  clients collapse a literal `../` before the request leaves, and Juice Shop
  filters the plain form. The encoded form is what the LFI rule is there to
  catch.
- **Expected (WAF on):** **blocked (403)** with a `cf-ray`; Security Events
  attributes it to the Cloudflare Managed Ruleset LFI rule.

## 1.4–1.12. Extended OWASP Top 10:2025 coverage — deprioritized

> Out of committed demo scope since 26 October 2026, retained for the delivery
> team. Payloads are kept here so whoever picks these up does not have to
> reconstruct them.

| # | Test | Endpoint | Test vector | Cloudflare control | Expected |
| - | ---- | -------- | ----------- | ------------------ | -------- |
| ~~1.4~~ | ~~Broken Access Control~~ | ~~`GET /rest/admin/application-configuration`~~ | ~~request the admin config route with no valid admin JWT~~ | ~~Core Ruleset (anomaly / forced browsing)~~ | ~~Blocked or challenged before origin~~ |
| ~~1.5~~ | ~~Security Misconfiguration~~ | ~~`GET /.env`, `GET /server.js`~~ | ~~direct GET of hidden env/source files at web root~~ | ~~Exposed credentials / bad extensions~~ | ~~Blocked (403)~~ |
| ~~1.6~~ | ~~Software Supply Chain~~ | ~~`GET /api/dependencies`~~ | ~~`X-Api-Version: ${jndi:ldap://…/a}` (Log4Shell-style)~~ | ~~Core Ruleset / virtual patching~~ | ~~Blocked (403)~~ |
| ~~1.7~~ | ~~Cryptographic Failures~~ | ~~`POST http://$DEMO_HOST/rest/user/login`~~ | ~~same login over plain HTTP instead of HTTPS~~ | ~~Always Use HTTPS / HSTS~~ | ~~Redirected to HTTPS (301/308) or blocked~~ |
| ~~1.8~~ | ~~Insecure Design~~ | ~~`POST /api/users/forgot-password`~~ | ~~repeated recovery requests to enumerate accounts~~ | ~~Rate limiting / bot management~~ | ~~Rate-limited or challenged past threshold~~ |
| ~~1.9~~ | ~~Authentication Failures~~ | ~~`POST /rest/user/login`~~ | ~~10+ rapid sequential logins (<1 min) in a loop~~ | ~~Rate limiting — API brute force~~ | ~~Challenged, then 429/403~~ |
| ~~1.10~~ | ~~Software/Data Integrity~~ | ~~`POST /b2b/v2/orders`~~ | ~~manipulated serialized object in the body~~ | ~~Core Ruleset (insecure deserialization)~~ | ~~Blocked (403)~~ |
| ~~1.11~~ | ~~Logging & Alerting Failures~~ | ~~any blocked endpoint (e.g. 1.1)~~ | ~~after a block, verify the Security Events entry~~ | ~~Security Analytics / Logpush~~ | ~~Event logged with request detail, no sensitive payload~~ |
| ~~1.12~~ | ~~Exceptional Conditions~~ | ~~`GET /api/Challenges`~~ | ~~oversized / malformed parameters to force a backend error~~ | ~~Managed / custom rules~~ | ~~Handled gracefully; no stack trace leaked~~ |

Several of these (1.8, 1.9) depend on **rate limiting** and (1.8) on **bot
management**, which are separate features (specs `0003` and `0002`) rather than
the WAF; 1.7 and 1.11 are zone/observability settings. Picking them up means
pulling in those controls, which is why they sit outside the WAF demo's
committed scope.

## 2. Architecture points of attention

### 2.1. False-positive mitigation (health-check allow)

- **Business value:** uptime monitoring must not be blocked by WAF rules.
- **Endpoint:** the origin health path.
- **Method:** send a legitimate automated monitoring request (non-browser
  User-Agent) and confirm it is **allowed**, not caught by a generic rule.
- **Cloudflare control:** a WAF skip/allow rule scoped to the health path.

### 2.2. Origin isolation and WAF-bypass prevention

- **Business value:** an attacker must not be able to skip the WAF by reaching
  the origin directly; all inbound traffic is forced through the inspection edge.
- **Method:** from a separate network, make a direct request to the origin VM's
  address and confirm it **fails** (timeout or connection refused).
- **Expected:** the direct request does not complete.
- **Note — how this demo implements it:** origin isolation is enforced by the
  GCP firewall lock (`lock_origin_to_cloudflare = true`), which restricts
  80/443 on the VM to Cloudflare's published ranges, rather than by a Cloudflare
  Tunnel. The WAF module also *warns* at plan time if the origin is still open
  or the hostname is not proxied, since either lets the WAF be bypassed. See the
  runbook's "close the side door" step and spec `0001` (origin lockdown, FR-7).

## References

- [specs/0004-waf/spec.md](../specs/0004-waf/spec.md) — the WAF feature specification.
- [docs/wafdemo-owasp-juice-shop.md](wafdemo-owasp-juice-shop.md) — runbook: deploy, switch the WAF on/off, verify.
- `pt-cybersecurity-coe` Bruno collection — the executable `1.1`–`1.3` requests.
