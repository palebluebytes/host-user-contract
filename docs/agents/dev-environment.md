# Dev environment, formatting & linting

The detail behind the three rules in [`AGENTS.md`](../../AGENTS.md).

The contract flake inputs **only nixpkgs** (ADR-0002), so every dev tool comes from
`nix develop` rather than from a flake input — there is no `treefmt-nix`, no `git-hooks.nix`.

## The dev shell

`nix develop` (or direnv, via `.envrc`) provides `treefmt nixfmt ruff shfmt statix deadnix
shellcheck gh`, and points git at `.githooks` by setting `core.hooksPath`. Entering the shell
once is what enables the hook.

## Formatting

`nix fmt` runs treefmt over the whole tree: **nixfmt** (Nix), **ruff** (Python), **shfmt**
(shell). Config lives in `treefmt.toml`.

## The pre-commit hook

`.githooks/pre-commit` runs, in order:

| Step | Command |
| --- | --- |
| formatting | `treefmt --fail-on-change` |
| Nix lint | `statix check .` |
| dead Nix | `deadnix --fail .` |
| Python lint | `ruff check .` |

It first checks that `treefmt` is on PATH and exits with a clear message if not — that is the
failure you see when committing from a bare shell.

Shell scripts are **not** linted by the hook: greeter shell programs are `writeShellApplication`,
so shellcheck runs at build time instead. Standalone example scripts (e.g. the reference
keyFetcher) are shfmt-formatted and shellchecked directly.

## The lint config is curated

`statix.toml` ignores `.direnv` and disables four lints that fight the project's deliberate
idioms:

- flat `contract.x.y =` config (rather than nested attrsets),
- explicit assignments,
- `{ ... }:` module signatures,
- grouping parens.

The baseline is clean — keep it that way. If a new lint fires, fix the code rather than widening
the ignore list, unless it is fighting one of the idioms above.
