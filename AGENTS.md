# AGENTS.md

Agent-facing configuration for this repo. See `README.md` for what the project is and
`docs/adr/` for the design.

## Agent skills

### Issue tracker

Issues and PRDs live in the repo's GitHub Issues (`palebluebytes/host-user-contract`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `docs/adr/` plus a lazily-created `CONTEXT.md` (the glossary, written by `/grill-with-docs` as terms settle) at the repo root. See `docs/agents/domain.md`.
