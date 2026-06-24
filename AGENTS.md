# AGENTS.md

Agent-facing configuration for this repo. See `README.md` for what the project is and
`docs/adr/` for the design.

## Agent skills

### Issue tracker

Issues and PRDs live in the repo's GitHub Issues (`palebluebytes/host-user-contract`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one `CONTEXT.md` (the domain glossary) + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Dev environment, formatting & linting

The contract flake inputs **only nixpkgs** (ADR-0020), so all dev tools come from `nix develop`, not
from flake inputs (no `treefmt-nix`/`git-hooks.nix`).

- **Work inside `nix develop`** (or direnv): it provides `treefmt nixfmt ruff shfmt statix deadnix
  shellcheck gh` and points git at `.githooks`.
- **Format with `nix fmt`** — treefmt over the whole tree: nixfmt (Nix), ruff (Python), shfmt (shell).
  Config: `treefmt.toml`.
- **Commit from inside `nix develop`.** The `.githooks/pre-commit` hook runs `treefmt --fail-on-change`
  + `statix` + `deadnix` + `ruff` + `shellcheck`, and those tools are only on PATH in the dev shell —
  a `git commit` from a bare shell will be rejected with a clear message. (When committing via the
  Bash tool, use `nix develop --command git commit …`.)
- **Lint config is curated**: `statix.toml` ignores `.direnv` and disables four lints that fight the
  project's deliberate idioms (flat `custom.x.y =` config, explicit assignments, `{ ... }:` module
  signatures, grouping parens). The baseline is clean — keep it that way.
- Greeter shell programs are `writeShellApplication` (shellcheck runs at build time); standalone
  example scripts (e.g. the reference keyFetcher) are shfmt-formatted and shellchecked directly.
