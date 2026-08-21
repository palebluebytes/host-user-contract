# AGENTS.md

Agent-facing configuration for this repo. See `README.md` for what the project is and
`docs/adr/` for the design.

## Dev environment

All dev tools come from `nix develop` (the flake inputs **only nixpkgs**), not from flake
inputs — there is no `treefmt-nix` or `git-hooks.nix`.

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
nix flake check .                # the contract: synthetic conformance + runtime VMs
nix flake check ./examples/users # the reference user fleet
nix flake check ./examples/fleet # the reference host fleet
```

The two fleets carry their own checks because they need home-manager, which the contract does
not input — so nothing but running all three catches drift between them.
`.github/workflows/ci.yml` walks the same matrix.

The **`./` prefix is required** on the fleet targets: without it Nix reads `examples/fleet` as a
registry lookup and fails with `cannot find flake 'flake:examples/fleet' in the flake registries`,
which looks like a broken environment rather than a mistyped path.

New files must be **`git add`-ed before `nix flake check` sees them** — a flake only reads the
tracked tree.

## Commits are the changelog

Commit subjects are **load-bearing**, not housekeeping: release-please reads Conventional Commits
on `main` to compute the version bump and generate `CHANGELOG.md` (ADR-0024).

- **`type(scope): subject`** — a subject that doesn't parse is silently dropped from the changelog.
- **Mark breaks** with `!` or a `BREAKING CHANGE:` footer. This is load-bearing beyond the
  changelog: a break moves the **compatibility line**, and that is the only thing that makes a host
  refuse an already-published contractPackage. Pre-1.0 a break bumps the minor; a plain `feat:`
  bumps only the patch, because the compatibility digit must mean "breaking" and nothing else.
- **Changing `manifest.nix`'s field set is always a break.** Adding, removing or retyping a manifest
  field under `fix:` or `refactor:` leaves old packages passing a reader that expects the new shape.
  Commit it as `feat!:`.
- **Visible in the changelog:** `feat`, `fix`, `perf`, `refactor`, `docs`. **Hidden:** `test`,
  `chore`, `ci`, `build`, `style`.
- **Never hand-edit** `CHANGELOG.md`, `.release-please-manifest.json`, `version.nix`, or the
  `version` field in `conformance/fixtures/*/contract-manifest.json` — release-please owns all four
  and moves them together. The fixtures must track the version because `readManifest` gates on it;
  if they ever fall behind, the byte-equality check fails on `main` and one regeneration fixes it.

## Agent skills

- **Issue tracker** — issues and PRDs live in this repo's GitHub Issues
  (`palebluebytes/host-user-contract`), via the `gh` CLI.
  See [`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).
- **Triage labels** — `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`,
  `wontfix`. Each canonical role maps to a label of the same name.
- **Domain docs** — single-context: one `CONTEXT.md` (the glossary) + `docs/adr/` at the root.
  See [`docs/agents/domain.md`](docs/agents/domain.md).
