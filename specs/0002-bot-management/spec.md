# 0002 — Bot management

| Field     | Value |
| --------- | ----- |
| Status    | Draft |
| Owner     | d.de.freitas.alves |
| Created   | 2026-10-21 |
| Updated   | 2026-10-29 |
| AI usage  | Vendor-side only. Cloudflare classifies bots with machine-learning models (bot score, heuristics, TLS/HTTP fingerprinting) that run at the edge. We configure the outcome, we do not train or host a model, and nothing AI-related is generated into the working tree — so no new `.gitignore` entries are needed beyond the existing assistant-tooling block. See [docs/conventions.md](../../docs/conventions.md). |

## Summary

Show that Cloudflare distinguishes automated traffic from an ordinary browser
on the demo application. A bounded simulator exercises six synthetic bot-abuse
scenarios without real credentials or form submissions.

## Context

First feature in the backlog, by owner decision. It is also the one with the
proven groundwork: the CapAct MVP's first lab was named "Cloudflare Bot Handling",
and the notification email it generates already tells the lab requester to
simulate a bot with a `curl` cron job against `/api/message`. The origin, the
bot simulation method and the load generator all exist — what is missing is the
edge in front of them.

For an RFP audience, bot management is the capability that is hardest to argue
about with a slide and easiest to show with a terminal: the same request,
accepted before and refused after, with a reason attached.

Depends on `0001`. Nothing here can be demonstrated until there is a proxied
hostname and the origin refuses direct traffic — otherwise the "blocked" request
can simply be retried against the origin URL.

## Mandatory scope (29 October 2026 update)

The RFP update of 29 October 2026 makes bot protection a **mandatory**
requirement, and requires it to be configured, operated, monitored and
continuously tuned **per application**. At minimum it must cover the six abuse
categories below. Each is fundamentally a bot problem — automated clients acting
at scale — so each is addressed with the same Cloudflare signals (bot score,
verified-bot detection, fingerprinting) combined with request velocity, rather
than with a hand-written rule per attack.

| # | Category | What it looks like | Primary Cloudflare signal | Needs a login flow |
| - | -------- | ------------------ | ------------------------- | ------------------ |
| 1 | Brute-force attacks | Many credential guesses at one account or endpoint | Bot score + velocity on the auth route | Yes |
| 2 | Malicious scraping | Automated harvesting of catalogue/content | Bot score, verified-bot check | No |
| 3 | Spam bots | Automated submissions to public forms | Bot score on form POSTs | No |
| 4 | Automated form abuse | Scripted misuse of a form workflow | Bot score + velocity on form POSTs | No |
| 5 | Account takeover (ATO) | Automated login with breached/guessed credentials | Bot score + velocity + leaked-credential check | Yes |
| 6 | Credential stuffing | Replaying leaked username/password pairs at scale | Bot score + velocity + leaked-credential check | Yes |

Categories 1, 5 and 6 need a real login flow, which the platform's whiteboard
app does not have; see Open questions on the demo target. Categories 2–4 are
expressible against the existing app or against Juice Shop. Where a category is
inherently about request volume (1, 5, 6), **bot signals decide _who_ is acting
and velocity decides _how much_** — pure volumetric limiting is `0003`, folded
in here (see Non-goals).

## Goals

- A scripted client is identified as automated and mitigated at the edge.
- A real browser reaching the same hostname is unaffected.
- A client that lies about being a well-known crawler is still caught, showing
  that verification is not based on the user agent.
- The effect is quantified: requests sent versus requests that reached origin.
- The mitigation is expressed as code, reviewable and toggleable.
- Six synthetic scenarios can be exercised: brute force, malicious scraping,
  spam bots, automated form abuse, account takeover and credential stuffing.

## Non-goals

- Delivering a production-tuned configuration. Per-application tuning and
  monitoring are in scope as a demonstrated capability and an RFP answer (29 Oct
  update), but the demo does not ship a hardened per-tenant baseline.
- Carding / payment-fraud scenarios. Related to credential stuffing, but the
  demo app has no payment flow.
- Pure volumetric rate limiting as a standalone control — that is `0003`, now
  folded into this feature and API Security. Bot-specific brute-force and
  credential-stuffing detection (bot signals plus velocity) is in scope here.

## Scenarios

**S-1 — Scripted client is mitigated**

- **Given** the hostname is proxied by Cloudflare and bot mitigation is off
- **When** a `curl` loop calls `/api/message` and the origin counter is read
- **Then** the requests arrive, establishing the baseline
- **And when** bot mitigation is enabled and the same loop is repeated
- **Then** the client is refused at the edge and the origin counter does not move

**S-2 — Real user is unaffected**

- **Given** bot mitigation is enabled
- **When** a presenter loads the hostname in a browser and posts a message
- **Then** the page works normally and the message appears

**S-3 — Spoofed crawler is caught**

- **Given** bot mitigation is enabled
- **When** a request claims `User-Agent: Googlebot`
- **Then** it is still mitigated, because Cloudflare verifies crawlers by
  network identity rather than by the user agent string

**S-4 — Volume attack is absorbed**

- **Given** bot mitigation is enabled
- **When** the load generator drives sustained traffic at the hostname
- **Then** the edge absorbs it, the origin counter stays flat, and the load
  generator's own metrics show what was sent

**S-5 — Credential abuse against a login flow is mitigated**

- **Given** bot mitigation is enabled on an application with a login endpoint
- **When** an automated client replays many username/password pairs at the login
  (credential stuffing) or hammers one account (brute-force)
- **Then** the attempts are mitigated at the edge on bot score and velocity —
  and, where enabled, Cloudflare's leaked-credential detection flags known
  breached pairs — while a human logging in is unaffected

## Functional requirements

| ID | Requirement | Scenario |
| ---- | ----------- | -------- |
| FR-1 | Bot mitigation is defined in Terraform as its own module, behind `enable_bot_management`, rendered into each demo by the wizard. | S-1 |
| FR-2 | With the feature off, a scripted client reaches the origin — the baseline is reproducible. | S-1 |
| FR-3 | With the feature on, a scripted client is refused at the edge and never reaches the origin. | S-1 |
| FR-4 | A standard browser session is unaffected by the feature. | S-2 |
| FR-5 | A request spoofing a verified-crawler user agent is mitigated. | S-3 |
| FR-6 | The mitigation action is configurable (block, managed challenge, JS challenge) without restructuring the module. | S-1 |
| FR-7 | Mitigated requests are identifiable in Cloudflare's event log with the matched rule and action. | S-1, S-4 |
| FR-8 | Sent-versus-arrived counts are readable for a demo window. | S-1, S-4 |
| FR-9 | Mitigation is driven by the Cloudflare bot score against a configurable threshold — not by matching user-agent strings. | S-1, S-3 |
| FR-10 | Bot analytics show the score distribution for the demo window, so the audience sees classification rather than just a verdict. | S-4 |
| FR-11 | Each of the six mandatory abuse categories (brute-force, scraping, spam, form abuse, account takeover, credential stuffing) is covered by a documented rule or managed feature, mapped in "Mandatory scope". | S-1, S-5 |
| FR-12 | Brute-force, account-takeover and credential-stuffing coverage is demonstrated against a real login flow, combining bot score with request velocity. | S-5 |
| FR-13 | Configuration, mitigated-event monitoring and tuning are scoped per application (per hostname/route), not as a single zone-wide setting. | S-1, S-5 |

## Non-functional requirements

| ID | Requirement | Target |
| ----- | ----------- | ------ |
| NFR-1 | Baseline-to-mitigated switch during a live demo | Under 60 seconds, no environment rebuild |
| NFR-2 | Browser impact | No visible challenge for an ordinary visitor |
| NFR-3 | Repeatability | The full sequence can run twice in a row with the same result |

## Acceptance criteria

- [ ] Feature off: scripted `curl` returns 200 and the origin counter increments.
- [ ] Feature on: the same `curl` is refused at the edge and the origin counter does not move.
- [ ] Feature on: a browser loads the app and posts a message successfully.
- [ ] Feature on: `curl -A Googlebot` is mitigated.
- [ ] Cloudflare's event log shows the matched rule and action for the mitigated requests.
- [ ] Load generator metrics and the origin counter are captured for the same window, showing the gap.
- [ ] Enabling and disabling the feature is a single toggle with no origin changes in the plan.
- [ ] The rule matches on bot score, and changing the threshold changes what is mitigated.
- [ ] Bot analytics for the demo window show the score distribution.
- [ ] Each of the six mandatory categories maps to a rule or managed feature in the module, per "Mandatory scope".
- [ ] A login flow is in place (Juice Shop or an added whiteboard login) so brute-force, ATO and credential stuffing are demonstrable, not only described.

## Open questions

| Question | Owner | Resolution |
| -------- | ----- | ---------- |
| Which Cloudflare plan? This decides the whole shape of the feature. | d.de.freitas.alves | **Resolved 2026-10-21 — Enterprise with the Bot Management add-on.** `cf.bot_management.score` is available for custom rules, along with verified-bot detection and bot analytics, so every requirement below is implementable as written. Still to verify: that the add-on is active on the demo zone itself (`0001` task 2). |
| Which mitigation action do we demo? Block is the clearest on a terminal; managed challenge is more realistic and shows Cloudflare preserving access for humans. A case can be made for showing both, one after the other. | | |
| Do we want to show a genuine verified bot being allowed through, not just a spoofed one being caught? That needs a real crawler hitting the zone, which is hard to arrange on demand. | | |
| What bot score threshold do we demo at? Cloudflare treats <= 30 as likely automated and 1 as definitely automated. A threshold of 30 is the defensible default, but the exact number is worth choosing deliberately since the audience will ask about false positives. | | |
| Which application hosts the login-dependent categories (brute-force, ATO, credential stuffing)? The platform whiteboard has no login; OWASP Juice Shop — already used for the WAF lab — does. | d.de.freitas.alves | Leaning Juice Shop, to reuse the WAF lab's origin and show a real auth flow. Alternative: add a minimal login to the whiteboard app. |
| Is Cloudflare's leaked-credential / exposed-credential detection in scope for the credential-stuffing and ATO categories? | | Available on our tier and would strengthen categories 5–6; confirm whether to enable it for the demo. |
| Does the move to the target **Azure EBC** environment change anything here? The groundwork runs in a personal Cloudflare/GCP lab today. | d.de.freitas.alves | Cloudflare config is origin-agnostic, so the rules should port unchanged; confirm the origin and zone once the EBC environment is decided. |
