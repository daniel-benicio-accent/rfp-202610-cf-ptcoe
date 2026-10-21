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
repository cold. Keep it **brief and objective**, and update it in the same
change that makes it stale — specifically when:

- a new demo component lands under `src/`;
- a spec reaches `Done`;
- the quick start commands change.

If a section is growing past a screen, move the detail into `docs/` and leave a
link behind.

## Where documentation lives

Two README files, and no others:

| File | Holds |
| ---- | ----- |
| [../README.md](../README.md) | Everything about the demo: purpose, backlog, layout, how to run it, component state. |
| [../specs/README.md](../specs/README.md) | The spec index, status and dependency graph. Linked from the root README. |

**Do not add a README to a component directory.** Scattering them means the
same fact gets written three times and two of the copies go stale. Supporting
detail goes in `docs/`; anything a reader needs in order to touch the code goes
in the code as a comment, next to the thing it explains.

A component still has to be documented — as a row in the root README's
component table, and as comments in its own source. It must also run from a
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

## Personal identifiers

Nothing in this repository names a personal domain, personal account or private
email address. Where an earlier project or a prerequisite has to be referred to,
use a placeholder instead:

| Real value | Write this instead |
| ---------- | ------------------ |
| `dbenicio.com` | `personal-domain-1` |
| `opsylab.com.br` | `personal-domain-2` |

Add a row when a new one comes up, and keep the numbering stable so existing
documents stay accurate.

The reason is scope, not secrecy: this repository goes to a client-facing bid
and may be handed over. A personal domain or account appearing in it reads as
either a mistake or an undeclared dependency, and neither is a good look in a
security proposal. The same logic is why a personal zone should not host the
demo itself.

Work identifiers are fine — spec owners, the Accenture distribution lists, the
repository's own remote.

## Secrets

Never commit credentials, tokens, endpoints with embedded keys, client data or
`.tfvars`. If a demo needs configuration, commit a `.example` file with dummy
values and document the real source.
