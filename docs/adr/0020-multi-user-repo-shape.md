# The `users` repo: a multi-user grouping of the operator's own accounts

**Status:** Accepted. **Extends** [ADR-0007](0007-user-flake-shape.md) (the single-user flake shape) — it does not replace it. Both shapes consume the contract identically, via `bindContractPackage` (ADR-0016) per user.

[ADR-0007](0007-user-flake-shape.md) fixed what *a* user flake exports: `identity.json`, a
contract-parameterized home module, its overlays. It framed the user singular. But a fleet operator
runs **several of their own accounts** — `inkpotmonkey`, the co-admin `eyeofalligator`, a break-glass
`admin`. One repo *per* account is heavy for accounts a single person owns and re-keys.

## Two populations of users

The distinction that resolves the shape question:

- **The operator's own accounts.** All managed by one person, who already holds every key and does
  every re-key. Grouping them in one **`users` monorepo** is natural: shared modules, shared CI, one
  visibility decision. There is no trust boundary *between* these accounts to protect at the repo
  layer — it is all the same operator.
- **Untrusted roaming users** (the anyHost greeter, [ADR-0006](0006-anyhost-greeter-runtime-binding.md), issue #2). A stranger brings their **own** single-user flake by URL. They must **not** share the operator's repo.

Both are consumed the same way: the binding is **per user** (`bindContractPackage { contractPackage
= users…<user>-contractPackage; identity; grants; }`), indifferent to whether users are grouped in
one repo or scattered across many.

## Decision

**A multi-user `users` repo is a supported ADR-0007 shape for the operator's own accounts.** Layout:

```
users/                              # the repo (the flake)
  flake.nix                         # maps over users/* → per-user homeConfigurations + <user>-contractPackage
  modules/  platform.nix  overlays/   # SHARED, keyed on config.identity.username (no identity baked in)
  users/                            # ALL the accounts live here, one subdir each
    <user>/ { identity.json, home.nix, secrets/ }   # per-user; secrets only if the user has a secret
```

- **Shared code, per-user data.** The home modules are keyed on `config.identity.username`, so the
  same `signing.nix`/`git.nix` serve every user; identity/home/secrets are per-user subdirs under
  `users/`.
- **Per-user outputs.** `homeConfigurations.<user>` and `packages.<sys>.<user>-contractPackage`, one
  set per user × grant variant. A host binds each user's package independently.
- **Per-user secret isolation.** Each user's `secrets/` is encrypted to **that user's own key alone**
  (per-user `.sops.yaml`), so co-location never lets one user decrypt another's secret.

## Consequences

- **One visibility for the repo** ([ADR-0019](0019-login-credential-travels-with-the-user.md)): a
  public `users` repo makes *every* member's yescrypt login hash public together — correct under the
  self-contained-user model, but it means a user needing a different visibility posture does not
  belong in the shared repo (they get their own).
- **Shared write access** is acceptable *because* these are one operator's own accounts. It is
  precisely why a genuinely independent/untrusted user still gets a separate repo — the multi-user
  repo carries no user-to-user trust boundary.
- **Confinement is unchanged and still per-home.** Each user's home has no system channel
  (ADR-0002); grouping changes nothing about the host-facing surface.
- **A user's SYSTEM config does not migrate.** When an account is moved in from the fleet, only its
  home-owned part (packages, dotfiles, mime) comes to the confined repo; any system settings its old
  fleet module carried (services, kernel/boot, autoUpgrade) stay **host**-owned on the seat that runs
  the user — they are unexpressible in a confined home, by design.
