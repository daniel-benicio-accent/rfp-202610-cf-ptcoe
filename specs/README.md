# Specifications

Live index of every specification in this repository. Add a row when you create
a spec; update the status as it moves. The workflow and status values are
described in [../docs/spec-workflow.md](../docs/spec-workflow.md).

| ID | Title | Status | AI usage | Links |
| -- | ----- | ------ | -------- | ----- |
| 0001 | Platform foundation | Draft | None | [spec](0001-platform-foundation/spec.md) · [plan](0001-platform-foundation/plan.md) · [tasks](0001-platform-foundation/tasks.md) |
| 0002 | Bot management | Draft | Vendor-side ML | [spec](0002-bot-management/spec.md) · [plan](0002-bot-management/plan.md) · [tasks](0002-bot-management/tasks.md) |
| 0003 | Rate limiting | Backlog | — | not scaffolded |
| 0004 | WAF | Backlog | — | not scaffolded |
| 0005 | DDoS protection | Backlog | — | not scaffolded |
| 0006 | API security | Backlog | — | not scaffolded |

`0003`–`0006` are agreed scope but not yet written. Scaffold each one when it
comes up the backlog, so numbers stay sequential and nothing sits half-specified.
Priority order and the reasoning behind it are in the root
[README.md](../README.md#backlog).

## Dependencies

`0001` gates everything. Until there is a Cloudflare-proxied hostname and an
origin that refuses direct traffic, no edge feature can be demonstrated
honestly — a "blocked" request could just be retried against the origin URL.

```
0001 ──┬── 0002  bot management
       ├── 0003  rate limiting
       ├── 0004  WAF
       ├── 0005  DDoS protection
       └── 0006  API security
```

## Creating a spec

```powershell
./scripts/new-spec.ps1 -Title "Rate limiting"
```

```bash
./scripts/new-spec.sh "Rate limiting"
```

Both scaffold `specs/NNNN-slug/` with `spec.md`, `plan.md` and `tasks.md` from
[_templates/](_templates/), numbered sequentially.
