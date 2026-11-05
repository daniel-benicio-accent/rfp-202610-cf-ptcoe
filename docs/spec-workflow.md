# Spec-driven workflow

Specifications are the source of truth in this repository. Code exists to
satisfy a spec, never the other way around.

## Lifecycle

```
idea -> spec.md -> review -> plan.md -> tasks.md -> code -> demo
          (what)              (how)     (steps)
```

Every feature lives in its own folder: `specs/NNNN-kebab-slug/`.

| File      | Answers                                   | Rule |
| --------- | ----------------------------------------- | ---- |
| `spec.md` | What is being built and why                | No implementation detail. A non-engineer must be able to read it. |
| `plan.md` | How it will be built                       | Written only after the spec is `Approved`. |
| `tasks.md`| The ordered breakdown of work              | Each task maps to at least one requirement ID from `spec.md`. |

## Status values

| Status        | Meaning |
| ------------- | ------- |
| `Draft`       | Being written. Not ready for review. |
| `Approved`    | Reviewed and agreed. Planning and coding may start. |
| `In progress` | Code is being written against it. |
| `Done`        | Implemented, demoed and verified against the acceptance criteria. |
| `Superseded`  | Replaced by another spec. Record which one. |

## Rules

1. **No code without an approved spec.** If something needs building, write the
   spec first — even a short one.
2. **Requirements get IDs.** `FR-1`, `NFR-1`. Tasks and tests reference them.
3. **Change the spec, not the memory.** If reality diverges from the spec during
   implementation, update `spec.md` in the same change.
4. **Open questions are tracked, not hidden.** Unknowns go in the spec's
   "Open questions" section and block approval until resolved or explicitly
   deferred.
5. **Register every new spec** in [../specs/README.md](../specs/README.md).
6. **No feature leaves Draft without rollout notes.** See below.

## Rollout notes

Every `plan.md` ends with a `## Rollout notes` section: tips for whoever runs
the demo, and the steps to stand the feature up.

Once a feature leaves `Draft` — whatever its next status, including the
backlog's `WIP` and `PoC done` markers in
[../specs/README.md](../specs/README.md) — that section must hold **at least one
note with tips for demonstrating it**. Move the status and add the note in the
same change.

When there is nothing to say yet, use the standard disclaimer, word for word, so
the placeholders are easy to find later:

> **Demo notes pending.** No demonstration tips have been written for this
> feature yet. Rehearse it end to end against the acceptance criteria in
> `spec.md` before showing it to anyone.

The wording is provisional. Change it here first, then wherever it is used:

```bash
grep -l 'Demo notes pending' specs/*/plan.md     # features still on the placeholder
grep -L '^## Rollout notes' specs/*/plan.md      # plans missing the section
```
