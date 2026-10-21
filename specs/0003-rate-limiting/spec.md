# 0003 — Rate limiting

| Field     | Value |
| --------- | ----- |
| Status    | Draft |
| Owner     | TBD |
| Created   | 2026-10-21 |
| Updated   | 2026-10-21 |
| AI usage  | AI assistant used to draft this specification from user-provided requirements; no AI models or artifacts are part of the demo. |

## Summary

Show that Cloudflare rate limiting protects the demo login endpoint from
excessive requests by challenging and blocking traffic above a defined
threshold. The demonstration uses simulated traffic to illustrate protection
against credential stuffing, brute force and resource exhaustion.

## Context

Rate limiting is the third feature in the backlog and depends on `0001`. The
demo needs a Cloudflare-proxied hostname and an origin that refuses direct
traffic, so requests cannot bypass the edge.

The presenter will simulate `POST /api/login` traffic in a test range of 50 to
150 requests per second. Cloudflare will apply a threshold of 10 requests per
minute to that endpoint, with Managed Challenge followed by Block as the
intended mitigation. The resulting challenged and blocked requests should be
observable during the demo.

## Goals

- Apply a rate limit to `POST /api/login` and mitigate traffic above 10 requests
  per minute.
- Demonstrate the mitigation using simulated traffic, not a real attack.
- Make the challenge and block outcomes observable during the demo.
- Keep requests within the configured limit usable.
- Allow the rate-limiting feature to be enabled and disabled independently.

## Non-goals

- Implementing authentication or changing login behavior.
- Protecting endpoints other than `/api/login`.
- Tuning rate limits for a production traffic profile.
- Generating real credential-stuffing or brute-force traffic.

## Scenarios

**S-1 — Excess login traffic is challenged and blocked**

- **Given** the demo hostname is proxied through Cloudflare and rate limiting is
  disabled
- **When** the presenter sends simulated `POST /api/login` traffic
- **Then** the traffic reaches the origin, establishing the baseline
- **And when** the presenter enables rate limiting and repeats the simulation
  across the test range of 50 to 150 requests per second
- **Then** requests above 10 per minute are challenged and blocked, and the
  mitigation is visible in Cloudflare

**S-2 — Requests within the limit are unaffected**

- **Given** rate limiting is enabled
- **When** the presenter sends no more than 10 `POST /api/login` requests in a
  minute
- **Then** those requests are not challenged or blocked by this rate limit

## Functional requirements

| ID   | Requirement | Scenario |
| ---- | ----------- | -------- |
| FR-1 | The rate limit matches requests to `POST /api/login`. | S-1, S-2 |
| FR-2 | The limit is 10 requests per minute; requests above the limit are mitigated. | S-1, S-2 |
| FR-3 | The demo can generate simulated traffic in a test range of 50 to 150 requests per second. | S-1 |
| FR-4 | Rate limiting can be enabled and disabled independently of the other edge features. | S-1 |
| FR-5 | The mitigation uses Managed Challenge followed by Block for excessive requests. | S-1 |
| FR-6 | Requests within the limit are not challenged or blocked by this rate limit. | S-2 |
| FR-7 | The presenter can identify the matched rate-limit rule and mitigation action in Cloudflare. | S-1 |

## Non-functional requirements

| ID    | Requirement | Target |
| ----- | ----------- | ------ |
| NFR-1 | Traffic used to demonstrate the feature is simulated and repeatable. | Test range of 50 to 150 requests/second against the demo endpoint |
| NFR-2 | The presenter can switch the feature on or off during the demo without rebuilding the environment. | No environment rebuild |

## Acceptance criteria

- [ ] The demo sends simulated `POST /api/login` traffic in a test range of 50 to 150 requests per second.
- [ ] The rate limit is configured for 10 requests per minute on `POST /api/login`.
- [ ] Requests above the limit receive Managed Challenge and are then blocked.
- [ ] Requests within the limit are not challenged or blocked by this rate limit.
- [ ] Cloudflare shows the matched rate-limit rule and mitigation action for challenged and blocked requests.
- [ ] Rate limiting can be enabled and disabled independently without rebuilding the environment.

## Open questions

| Question | Owner | Resolution |
| -------- | ----- | ---------- |
