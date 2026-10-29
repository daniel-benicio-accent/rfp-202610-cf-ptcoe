# Working agreements

## Language

**All written output in this repository is English** — specifications, README
files, code, comments, commit messages and pull request descriptions. This holds
regardless of the language used in conversation, meetings or chat. Discussion
happens in whatever language is convenient; the artifact is always English.

## Naming

| Thing            | Convention                  | Example |
| ---------------- | --------------------------- | ------- |
| Spec folder      | `NNNN-kebab-slug`           | `0001-customer-onboarding-flow` |
| Component folder | `src/kebab-slug`            | `src/onboarding-api` |
| Branch           | `NNNN-kebab-slug`           | `0001-customer-onboarding-flow` |
| Requirement ID   | `FR-n` / `NFR-n`            | `FR-3` |

Spec numbers are sequential and never reused, including for abandoned specs.

## README upkeep

The root [README.md](../README.md) is the entry point for anyone who opens this
repository cold. Keep it **brief and objective** — the big picture and how to
get started — and update it in the same change that makes it stale,
specifically when:

- the repository layout changes;
- the quick start commands change.

Backlog, spec status and component state belong in
[../specs/README.md](../specs/README.md), not here.

If a section is growing past a screen, move the detail into `docs/` and leave a
link behind.

Both READMEs open with their purpose, followed by a **Contents** list linking
every section. Add, rename or remove a heading and the Contents list changes in
the same edit.

## Where documentation lives

Two README files, and no others:

| File | Holds |
| ---- | ----- |
| [../README.md](../README.md) | The big picture and how to start: purpose, what the demo shows, key decisions, repository map and layout, quick start. |
| [../specs/README.md](../specs/README.md) | Backlog and priorities, the spec index and status, component state, and the dependency graph. Linked from the root README. |

**Do not add a README to a component directory.** Scattering them means the
same fact gets written three times and two of the copies go stale. Supporting
detail goes in `docs/`; anything a reader needs in order to touch the code goes
in the code as a comment, next to the thing it explains.

A component still has to be documented — as an entry in its spec's row of
[../specs/README.md](../specs/README.md), and as comments in its own source. It must also run from a
clean checkout, with no step that only exists on someone's laptop.

## AI-related specifications

When a specification covers, uses or mentions AI (models, agents, assistants,
prompts, RAG, embeddings), its local tooling and generated artifacts must get a
matching entry in [../.gitignore](../.gitignore) — assistant config directories,
prompt caches, chat histories, model weights, vector stores, API key files.

The reason is that AI tooling writes machine-specific state and credentials into
the working tree by default. Those must never reach the remote.

The spec template carries an **AI usage** field; filling it in with anything
other than `None` is the trigger to review `.gitignore` before the spec is
approved.

## Secrets

Never commit credentials, tokens, endpoints with embedded keys, client data or
`.tfvars`. If a demo needs configuration, commit a `.example` file with dummy
values and document the real source.
