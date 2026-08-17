# AGENTS.md

Agent-facing configuration for this repo. See `README.md` for what the project is and
`docs/adr/` for the design.

## Dev environment

All dev tools come from `nix develop` (ADR-0004: the flake inputs **only nixpkgs**), not from
flake inputs — there is no `treefmt-nix` or `git-hooks.nix`.

- **Work inside `nix develop`** (or direnv).
- **Format with `nix fmt`** before committing — treefmt over the whole tree.
- **Commit from inside the shell** — `.githooks/pre-commit` needs those tools on PATH, and a
  `git commit` from a bare shell is rejected. Via the Bash tool:
  `nix develop --command git commit …`

Detail — the hook's checks, the curated lint config, shell-program conventions:
[`docs/agents/dev-environment.md`](docs/agents/dev-environment.md).

## Verifying a change

"Run everything" is `nix flake check` in **three** targets:

```
nix flake check .              # the contract: synthetic conformance + runtime VMs
nix flake check examples/users # the reference user fleet
nix flake check examples/fleet # the reference host fleet
```

The two fleets carry their own checks because they need home-manager, which the contract does
not input (ADR-0004/0022) — so nothing but running all three catches drift between them.
`.github/workflows/ci.yml` walks the same matrix.

## Agent skills

- **Issue tracker** — issues and PRDs live in this repo's GitHub Issues
  (`palebluebytes/host-user-contract`), via the `gh` CLI.
  See [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).
- **Triage labels** — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`,
  `wontfix`. Each canonical role maps to a label of the same name.
- **Domain docs** — single-context: one `CONTEXT.md` (the glossary) + `docs/adr/` at the root.
  See [`docs/agents/domain.md`](docs/agents/domain.md).
