# The `users` repo: a multi-user grouping of the operator's own accounts

**Status:** Accepted. **Extends** [ADR-0007](0007-user-flake-shape.md) (the single-user flake shape) — it does not replace it. Both shapes consume the contract identically, via `bindContractPackage` (ADR-0016) per user. **Amended in place (2026-08-15, issue #36)** — sharing modules/overlays is permitted, not required, and the home parameterization gains an `inputs` specialArg; see the amendment at the end. **Amended again (2026-08-16, issue #57)** — the layout rule is now derived by the contract's own `mkContractRoster` rather than transcribed per producer. The decision and its reasoning stand.

> **Terminology note (2026-08-17, [ADR-0030](0030-one-name-per-value-on-the-producer-surface.md)):** this record says **roster**; the code and `CONTEXT.md` now say **member set / `mkMembers`**. The decision below is unchanged — only the vocabulary moved. This ADR is left as written.


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
  modules/  platform.nix  overlays/   # shareable, keyed on config.identity.username (no identity
                                      # baked in) — permitted, not required
  users/                            # ALL the accounts live here, one subdir each
    <user>/ { identity.json, home.nix, secrets/ }   # per-user; secrets only if the user has a secret
```

- **Shared code, per-user data.** The home modules are keyed on `config.identity.username`, so the
  same `signing.nix`/`git.nix` *can* serve every user; identity/home/secrets are per-user subdirs
  under `users/`. (An ergonomic the repo may earn, **not** an obligation of the shape — amended
  below.)
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

## Amendment (2026-08-15) — sharing is permitted, not required (issue #36)

The layout above reads as normative on one point where it should only illustrate: that the
root-level `modules/` and `overlays/` are *shared*. **Sharing modules and overlays across a
multi-user repo is permitted, not required.** A `users` repo that scopes its modules and overlays
per user is exercising a permitted variant of this shape, not drifting from it.

The loosening is evidence-driven, from the operator's own `users` repo: the sharing there turned out
to be largely coincidental. **Of eleven modules, only two are imported by more than one user** — and
both copies get *smaller* when duplicated, the second user's copy losing a whole profile bundle and a
secrets-only environment variable it never used. The **overlays are consumed by exactly one user's
modules**, so the other user's `pkgs` was eval-depending on three heavy external flakes for nothing.
Sharing that is not earned costs clarity *and* eval, and a repo should not be read as non-conforming
for declining to pay it.

Per-user placement — `users/<user>/modules/`, `users/<user>/overlays/`, or simply a fatter
`home.nix` — is as conforming as the root-level `modules/`/`overlays/` the layout block draws; the
block illustrates one arrangement, it does not fix where a module may live.

An operator who *wants* to enforce a common setup across a set of users still can, and this ADR's
mechanism is still how: key the shared home module on `config.identity.username` and import it from
each user's `home.nix`. The worked example is the shared-module/overlay reference pair in
`examples/users/shared/`, imported by the `duo-a`/`duo-b` roster members and proved by that flake's
`shared-code-per-user-data` check (issue #37). *Conflicts with*
[ADR-0022](0022-reference-fleets-and-the-test-split.md)'s "no shared home modules in
`examples/users/`" — deliberately: that decision reasoned there was nothing *universal* to factor
across the reference users, which stands; the pair is added to demonstrate the **permitted**
mechanism, not to factor the reference homes. ADR-0022 records the exception in its own 2026-08-15
amendment.

**The `inputs` specialArg.** A home's parameterization gains `inputs`:
`{ config, lib, hostFacts, inputs, ... }`. [ADR-0007](0007-user-flake-shape.md) fixes the home as
parameterized, with the contract and pkgs supplied by something else; once each home may declare its
**own** `nixpkgs.overlays`, whatever supplies pkgs must also hand the home the flake `inputs` those
overlays close over — otherwise a per-user overlay list is not expressible at all. A producer
supplies it exactly as it supplies `hostFacts`: `extraSpecialArgs.inputs = inputs` in the `users`
flake. This is a **producer-side convention, not a contract surface** — the contract depends only on
nixpkgs `lib` ([ADR-0004](0004-extract-contract-flake.md)) and neither reads nor requires `inputs`,
and an overlay that closes over nothing external never asks for it — which is why `examples/users`
still passes `hostFacts` alone even now that `duo-a`/`duo-b` declare `nixpkgs.overlays`: their shared
overlay closes over `prev` only. It is recorded here, rather than as an edit to
[ADR-0007](0007-user-flake-shape.md), for two reasons: the multi-user shape is where per-user
overlay lists arise, and ADR-0007's
`{ config, lib, hostFacts, ... }` already admits the argument — the `...` is literal, so naming
`inputs` adds a convention, not a contradiction.

**What does not change.** None of this ADR's reasoning weakens — only the internal-layout
illustration loosens:

- the **two populations** distinction — the operator's own accounts group in one repo; untrusted
  roaming users still bring their own single-user flake and never share the operator's;
- **per-user secret isolation** — each user's `secrets/` is still encrypted to that user's own key
  alone, so co-location never lets one user decrypt another's;
- **per-user outputs and the per-user bind** — unchanged, and still "indifferent to whether users are
  grouped in one repo or scattered across many," which is precisely what makes a later split of a
  per-user-scoped repo a non-event rather than a migration;
- the **single-visibility consequence** ([ADR-0019](0019-login-credential-travels-with-the-user.md))
  — a shared repo still makes every member's login hash public together, so a user needing a
  different visibility posture still does not belong in it.

## Amendment (2026-08-16) — the layout rule is contract-shipped (issue #57)

The layout above is a rule about a *directory*, and until now every producer implemented it itself:
a `readDir` over `users/` filtered on the presence of an `identity.json`, then an identity map over
the names it found. The contract then implemented it twice more, resolving
`<usersDir>/<name>/identity.json` inside `mkContractUser` and `<userDir>/identity.json` inside
`mkContractHome` — so each identity file was read two or three times per evaluation, by three
owners, and the rule this ADR states in prose had four independent transcriptions in code.

The contract now ships the derivation: **`mkContractRoster { usersDir } → { <name> = { name; dir;
identity; }; }`**, one **member** per subdir holding an `identity.json`
([ADR-0026](0026-consumer-producer-public-surface.md)'s amendment records it as public surface). The
producer coin and the home builder take a member, so no identity path is re-derived downstream. A
directory whose `home.nix` has landed but whose `identity.json` has not is skipped, as is a
non-directory entry; a `usersDir` holding no member at all is a named error rather than an empty
roster.

Nothing in this ADR's shape changes, and **liftability is the constraint it is written against**:
the roster reads `users/<u>/` and adds no index file, no manifest and no knowledge at the repo root,
so lifting one user out into its own single-user flake ([ADR-0007](0007-user-flake-shape.md)) stays
a literal directory move — and a single-user repo, having no roster to derive, still bakes by
handing `mkContractUser` a `name` + `usersDir` directly.
