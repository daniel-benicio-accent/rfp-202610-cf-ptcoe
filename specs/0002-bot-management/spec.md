# 0002 — Bot management

| Field     | Value |
| --------- | ----- |
| Status    | Draft |
| Owner     | d.de.freitas.alves |
| Created   | 2026-10-21 |
| Updated   | 2026-10-21 |
| AI usage  | Vendor-side only. Cloudflare classifies bots with machine-learning models (bot score, heuristics, TLS/HTTP fingerprinting) that run at the edge. We configure the outcome, we do not train or host a model, and nothing AI-related is generated into the working tree — so no new `.gitignore` entries are needed beyond the existing assistant-tooling block. See [docs/conventions.md](../../docs/conventions.md). |

## Summary

Show that Cloudflare distinguishes automated traffic from a real person in front
of the demo application, and that the chosen mitigation stops the bot while the
browser is unaffected.

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

## Goals

- A scripted client is identified as automated and mitigated at the edge.
- A real browser reaching the same hostname is unaffected.
- A client that lies about being a well-known crawler is still caught, showing
  that verification is not based on the user agent.
- The effect is quantified: requests sent versus requests that reached origin.
- The mitigation is expressed as code, reviewable and toggleable.

## Non-goals

- Tuning detection thresholds for a production traffic profile.
- Protecting a login or checkout flow. The demo app has neither.
- Credential stuffing or carding scenarios — related, but separate stories.
- Rate-based mitigation. That is `0003`; keeping them apart is what makes each
  one legible on its own.

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

## Open questions

| Question | Owner | Resolution |
| -------- | ----- | ---------- |
| Which Cloudflare plan? This decides the whole shape of the feature. | d.de.freitas.alves | **Resolved 2026-10-21 — Enterprise with the Bot Management add-on.** `cf.bot_management.score` is available for custom rules, along with verified-bot detection and bot analytics, so every requirement below is implementable as written. Still to verify: that the add-on is active on the demo zone itself (`0001` task 2). |
| Which mitigation action do we demo? Block is the clearest on a terminal; managed challenge is more realistic and shows Cloudflare preserving access for humans. A case can be made for showing both, one after the other. | | |
| Do we want to show a genuine verified bot being allowed through, not just a spoofed one being caught? That needs a real crawler hitting the zone, which is hard to arrange on demand. | | |
| What bot score threshold do we demo at? Cloudflare treats <= 30 as likely automated and 1 as definitely automated. A threshold of 30 is the defensible default, but the exact number is worth choosing deliberately since the audience will ask about false positives. | | |
