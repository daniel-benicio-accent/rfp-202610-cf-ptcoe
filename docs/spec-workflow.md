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
