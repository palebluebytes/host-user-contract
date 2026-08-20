# Runbook — repo-split capstone (issue #1)

Operator guide for the model-A → model-C cutover: moving a real user (`inkpotmonkey`)
into its **own repo** consumed by the fleet via `bindContractUser`.

> **⚠️ Written against an older surface.** The user side is now a **declaration** —
> `users/<u>/user.nix` naming the session shapes a user runs in and the home for each — and a host
> states what the machine can run (`contract.modes`) and what each person may do
> (`bindContractUsers { source; users; }`).
> `contract.wants` / `contract.supports` / `contract.requests`, the host-level `contract.affordances`
> option, and `traceUser` no longer exist. The *operational* shape of the cutover below is
> unchanged; where it quotes the surface, read [`README.md`](../../README.md) and
> [`CONTEXT.md`](../../CONTEXT.md) instead.

> **⚠️ Superseded stages ("the contract handles no secrets").** The contract
> now handles no secrets beyond the login credential. The secret-specific stages below are
> **obsolete** and retained only as historical context: **Stage 4** (grant a secret feature →
> per-feature re-key) and **Stage 5** (revoke → remove recipient + rotate) do not apply —
> there are no secret-bearing features, no `mkFeatureRecipients`, and no host recipients. In
> **Stage 6**, `contract.exposed` is now a plain host *fact* with no enforced ban (the
> `exposedHostOffenders` assertion was removed). A user's own home secrets, if any, ride the
> user's own key, provisioned by the user's own home module — never through the contract.

> **Why this is a runbook, not code.** The contract side this capstone consumes is already
> built and CI-proven here (`bindContractUser`/`mkContractUser`/`traceUser`, the example
> user flake, and — for acceptance criterion 2 — `conformance/confinement.nix`). What remains
> is **operational, cross-repo, and human-only**: creating a new repo and editing the fleet.
> Each step below marks whether it is an edit (AFK-safe) or a **🔑 trusted-machine** action.

ADR numbers below are this repo's contiguous set (`docs/adr/`). The originating issue cites
the *old* sparse numbers (e.g. "ADR-0023" = the user-flake shape, now
[0007](../adr/0007-user-flake-shape.md)/[0008](../adr/0008-greeter-is-a-contract-deliverable.md)/[0009](../adr/0009-binduser-single-identity-loader.md);
"ADR-0018 request channel" = now [0002](../adr/0002-user-confinement-manifest-greeter.md)).

## The three repos

| Repo | Role | Touched here |
| --- | --- | --- |
| `host-user-contract` (this) | The shared schema + `lib` (`bindContractUser`, `mkContractUser`, `traceUser`, …). | Input only — do not fork it into the user or fleet. |
| `user-inkpotmonkey` (**new**) | The user's home config, ADR-0007 shape. | Created in stage 1. |
| the fleet (`~/code/nixos`) | The hosts (`kelpy`, workstations) that consume the user. | Edited in stages 3–6. |

## Preconditions

- The fleet already pins `host-user-contract` as a flake input and imports
  `contract.nixosModules.default`.
- You have the fleet admin age key on a **trusted machine** (the box that re-keys sops).
  This key is never present on `kelpy` or any agent host.
- `sops` + `age` available in the dev shell.

---

## Stage 1 — create the user repo (ADR-0007 shape)

**Edit.** Model the new `user-inkpotmonkey` repo on a member of `examples/users/` in this repo (e.g.
`examples/users/users/ada/`) — the reference user fleet is the canonical reference for the shape
(ADR-0020/0022):

- `identity.json` — pure data (`name`, `email`, `username`). Loaded by the *binding*, never
  by the home (ADR-0009); the home reads `config.identity.{name,email}` for its dotfiles.
- `home.nix` — a **contract-parameterized home-manager module**: it declares which SESSION SHAPES
  it can run in (`contract.supports.*` — no default, at least one required, ADR-0032), what it asks
  for (`contract.wants.*`, defaulting to the safe set) and EMITS `contract.requests.*`, imports NO
  contract, writes NO system config. It gates session-specific content on
  `custom.home.profiles.<mode>.enable`, which the contract writes from the mode it built the home
  for; content that works in every session is written with no gate at all. It branches read-only on
  `hostFacts` (`exposed`, `platform`, `mode`), never on `osConfig`/`hostName`, and sees NO grant —
  a grant rides the bind and cannot change a home. Its `wants` and `supports` must NOT depend on
  `hostFacts` (ADR-0028: the grant is derived from the offer).
- `flake.nix` — inputs `contract` + `home-manager` (with `nixpkgs.follows` so there is ONE
  nixpkgs, ADR-0004); `checks = packages`, which gives the home-manager build the contract's own
  package-free suite cannot host **for free** — a `contractPackage` build-depends on its home's
  activation package, so building the check builds the home (this replaces the hand-written
  `checks.home-build` an earlier revision of this guide told you to write); and its contractPackages + binding
  index via `contract.lib.mkContractUser { name; homes; pkgs; usersDir }` (the singular producer;
  `mkContractUsers` for a multi-user repo) — the pre-built path (ADR-0016/0026). The offer is
  harvested from the home, not passed; the set of homes to build is each user's own
  `contract.supports` ∩ the modes `contract.modes`
  and narrowed per system by `contract.lib.mkHomeMatrix` (ADR-0030 renamed these from `variants`;
  `system` is no longer an argument — it is read off `pkgs`).

> **Confinement is structural (acceptance criterion 2), and it is now regression-proven** in
> `conformance/confinement.nix`: the home umbrella declares no `users.users`, `security.sudo`,
> `boot.*`, or `sops.*`, so those are *unexpressible* — a home that tries to set one fails to
> evaluate, it is not merely `mkIf`-denied. Keep the user home free of any imported module that
> would smuggle a system channel back in.

**Verify:** `nix build .#checks.<system>.<user>-contractPackage-<mode>` in the new repo builds the
home standalone — e.g. `nix build .#checks.x86_64-linux.ada-contractPackage-cli` against
`examples/users`. `nix flake check` builds every published mode for every member at once.

## Stage 2 — decide `hashedPassword` by repo visibility

**Edit + decision (record it in the user repo's README).**

- **Private repo** → plaintext `hashedPassword` in the repo; enable stays crypto-free.
- **Public/shared repo** → `hashedPassword` via **sops + yescrypt**; the host decrypts at build.

This is acceptance criterion 5. The rationale (which visibility, why) must be written down.

## Stage 3 — the fleet enables the user as an input

**Edit (fleet).** Add `user-inkpotmonkey` as a flake input and bind it turnkey. The user repo bakes
its contractPackages + binding index with `contract.lib.mkContractUser`/`mkContractUsers`; the fleet
declares what the machine runs (`contract.modes`) and binds each user with their affordances beside
them (`contract.lib.bindContractUsers { source; users; }`). The grant is what the host afforded —
there is no user-side half to intersect with, and no per-host grant matrix. This is the single,
pre-built binding mode; the user owns their nixpkgs pin and package set.

**Afford nothing yet.** A build whose affordances are empty proves the input wiring (acceptance
criterion 3, first half) — an ordinary desktop user needs no affordance at all.

**Verify:** `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` on a
workstation host builds with the user present and login-capable.

## Stage 4 — grant a secret-bearing feature → per-feature re-key 🔑

**🔑 trusted-machine.** This is the import + re-key two-step (acceptance criterion 3, second
half), driven by the contract's slice-06 tooling, `contract.lib.mkFeatureRecipients`:

1. **Edit (fleet):** set `grants.<secretFeature> = true` for the user on the granting
   host.
2. **Re-key (🔑):** `mkFeatureRecipients` reads the fleet's `nixosConfigurations` and returns,
   for each secret feature's **encrypted secret file** (its `featureMeta.<f>.secretFiles`
   entries), the set of hosts that grant it — the **single source of truth for that file's
   recipients**. Regenerate the `.sops.yaml` *creation rules* from that map so the recipient set
   matches, then re-encrypt each affected secret file to it:

   ```
   # on the trusted machine, in the repo that owns the secret
   # 1. edit .sops.yaml creation rules so <feature>'s path lists the recipients
   #    mkFeatureRecipients returned (includes the newly-granting host's age key)
   # 2. re-encrypt the SECRET FILE (not .sops.yaml) to the updated rules:
   sops updatekeys secrets/<feature>.yaml
   ```

   `sops updatekeys` operates on the **encrypted secret file**, re-encrypting it to whatever
   recipients `.sops.yaml` now resolves for its path — not on `.sops.yaml` itself. The granting
   host's age key is now a recipient; the secret resolves at runtime on that host.

> A **secret-bearing grant on an exposed host is a build error before any of this** — the
> `contract.exposed` ban (stage 6), enforced by the `exposedHostOffenders` assertion in
> `modules.nix`, not by `mkFeatureRecipients` itself (which has no exposed-host filter). So an
> exposed host can never reach the re-key step holding a secret feature.

**Verify:** switch the granting host; the feature's secret decrypts and the feature works at
runtime.

## Stage 5 — revoke a feature → remove recipient + rotate 🔑

**🔑 trusted-machine.** Acceptance criterion 4. Revoking must both drop the recipient **and
rotate the secret value** — a revoked host has already seen the plaintext:

1. **Edit (fleet):** set `grants.<secretFeature> = false` (or remove the user's grant).
2. **Re-key (🔑):** re-run `mkFeatureRecipients`; the revoked host is no longer in the recipient
   set. Update the `.sops.yaml` rules to match, then `sops updatekeys secrets/<feature>.yaml`
   re-encrypts the secret file, dropping the revoked host's key.
3. **Rotate (🔑):** generate a fresh secret value and re-encrypt to the new recipient set
   (`sops secrets/<feature>.yaml`, replace the value). Removing a recipient alone is not enough —
   the revoked host has held the ciphertext and could have cached the plaintext, so rotate.

**Verify:** the revoked host can no longer decrypt; a host that still grants the feature gets
the rotated value.

## Stage 6 — the exposed/agent host is login-only 🔑-free

**Edit (fleet).** On `kelpy` (exposed/agent-facing): set `custom.host.exposed = true` and grant
the user **login-only** (identity + gui at most, no secret-bearing feature). Acceptance
criterion 6.

The contract enforces this structurally: `custom.host.exposed = true` activates the assertion
in `modules.nix` (`exposedHostOffenders`) — the build **fails** if any user on the host is
granted a secret-bearing feature. So kelpy holding a feature secret is unbuildable, not merely
discouraged.

**Verify:** `nix build` of kelpy succeeds with login-only grants; adding a secret grant to any
user on kelpy makes the build fail the exposed-host assertion.

---

## Stage 7 — automated proof: the integration test rig (issue #1 T4)

Criteria 3 and 6 are proven in CI **without touching any production host** by a two-node
integration test, `~/code/nixos/parts/checks/prebuilt-bind-external/`
(`nix build .#checks.<system>.prebuilt_bind_external`). It binds the **real** external user home via
`bindContractPackage` on two synthetic seats:

- **`exposed`** — `custom.host.exposed = true`, grants `containers` only (was `workstation` before
  ADR-0024 split that role; the external check flips when it next updates its `contract` pin). Proves criterion 6: the
  account materializes, the home activates, git falls back to `~/.ssh`, and **no** signing secret
  is present.
- **`trusted`** — grants `signing`, and holds a throwaway key so sops-nix decrypts at runtime.
  Proves criterion 3 (runtime half): git's `signingkey` resolves to the sops-decrypted own-secrets
  secret (a real, dummy key).

Both seats bind a **generic test identity** (`tests/identity.json` — a throwaway `testuser` +
password), built from the *real* home modules, so the rig never fabricates an account from the real
user's credentials. The signing modules are keyed on `config.identity.username`, so the same module
serves the real user and the test user.

> **Contract fix surfaced by this rig.** `bindContractPackage`'s activation service originally ran
> `activate` as `User=<u>` with only `HOME=` — enough for the synthetic conformance package, but a
> real home-manager `activate` needs a login session (USER, PATH, a user systemd manager +
> `XDG_RUNTIME_DIR`) for its `sd-switch` step. `lib.nix` now runs it via
> `runuser -l <user> -c activate`; a seat should also **linger** the user so the home's user
> services persist past activation.

## The self-contained-user case — `signing` rides the USER's key, not a host recipient

Stages 4–5 describe re-key/rotate for a feature whose secret has **host recipients**
(`featureMeta.<f>.secretFiles`, driven by `mkFeatureRecipients`). The tracer feature `signing` is
**not** one of these: it is `secretBearing` but declares **no** `secretFiles`. Its key rides the
**user's own** home sops, decrypted by the user's own age key ([ADR-0019](../adr/0019-login-credential-travels-with-the-user.md),
the self-contained-user invariant: no host may own a user credential, else the north star's *any
host × any user* breaks).

For such a feature:

- **`mkFeatureRecipients` / `just sops-recipients` returns `{}`** — no host is ever a recipient, so
  there is nothing to re-key on grant and nothing to remove on revoke. That empty set *is* the
  criterion-6 guarantee in another form: the exposed host cannot hold what no host holds.
- **"Revoke + rotate" (criterion 4) is a USER-repo operation:** rotate the key in the user repo's
  own secrets (`sops secrets/users/<user>.yaml`), bump the public half in the home's `git.nix`,
  re-publish the user flake, then `nix flake update <user-input>` in the fleet — the trusted seat
  picks up the new key; the exposed seat is unaffected (it never had it).

Both re-key models coexist: **host-recipient features** use stages 4–5 (`mkFeatureRecipients` +
`sops updatekeys`); **user-key features** like `signing` rotate user-side. The capstone's tracer
exercises the latter.

---

## Stage 8 — publish & lock-bump ordering (T7)

**External/human, and ORDER-SENSITIVE.** During development the fleet's `prebuilt_bind_external`
check (Stage 7) is green **only** with dev overrides:

```
nix build .#checks.<system>.prebuilt_bind_external \
  --override-input contract path:/home/inkpotmonkey/code/host-user-contract \
  --override-input users    path:/home/inkpotmonkey/code/users
```

That override is load-bearing, not a convenience: the committed `flake.lock` pins an **older
contract rev that predates the `runuser -l` activation fix** (Stage 7), so binding it makes
`contract-activate-<user>.service` time out; and `users` is a local `path:` input **absent in any
clean CI checkout**. So the check is RED under the committed lock until the inputs are published.
Do this in order — a later step depending on an earlier one:

1. **Publish the contract** with the `runuser -l` fix committed (`host-user-contract` remote).
2. **Bump the fleet's contract pin:** `nix flake update contract`. The lock now carries the fix, so
   the activation service no longer times out.
3. **Publish `users`** (`palebluebytes/users` remote) with everything committed.
4. **Flip the fleet's `users` input** `path:` → `github:palebluebytes/users` and
   `nix flake update users`.
5. **Only now** does `nix build .#checks.<system>.prebuilt_bind_external` pass with **no** overrides
   — that green-without-overrides is the gate that the cutover inputs are actually published and
   pinned. Run it before relying on any production `bindContractPackage`.

> Until step 5 passes clean, **no production host may bind via `bindContractPackage`** — it would
> pin the same stale/absent inputs the check is guarding against.

---

## Acceptance checklist

- [x] **1.** User lives in a separate repo of the ADR-0007 shape, consumed via `bindContractPackage`. *(stages 1, 3; the `inkpotmonkey-home` repo + fleet input)*
- [x] **2.** Out-of-universe options are *unexpressible*, not merely rejected. *(stage 1; proven by `conformance/confinement.nix` generically + the user repo's `home-confinement` check against its real modules)*
- [x] **3.** A host enables the user as an input and builds; granting a secret feature resolves the secret at runtime. *(stage 7 `trusted` node; for `signing` there is no host re-key — see the self-contained-user case)*
- [x] **4.** Revoking a feature removes the recipient and rotates — **reframed** for a user-key feature: no host recipient exists, so rotate is user-side. *(self-contained-user case)*
- [x] **5.** `hashedPassword` handling matches the visibility decision (public → yescrypt in `identity.json`); rationale recorded. *(stage 2; [ADR-0019](../adr/0019-login-credential-travels-with-the-user.md), user repo `identity-yescrypt` check)*
- [x] **6.** The exposed host is login-only and holds no feature secrets. *(stage 7 `exposed` node; production `kelpy` cutover deferred to post full-home migration)*

> **Tracer status (issue #1).** The mechanism is proven end-to-end on a `base`+`git`+`signing`
> tracer home + the two-node integration rig (green with the Stage 8 dev overrides). Rewiring the 8
> **production** hosts to `bindContractPackage` is deferred until (a) the inputs are published and
> the lock bumped so the check is green with **no** overrides (Stage 8), and (b) the full home
> (gui/emacs/ai/git-annex) migrates into the user repo — binding the tracer home to a production
> host would strip that environment.

## What the contract already guarantees (do not re-implement)

- `mkContractUser` / `mkContractUsers` / `mkContractFleet` / `bindContractUser` / `traceUser` — the public producer/consumer surface (`lib.nix`, ADR-0026). The three producers are one user / a member set you enumerate / one you derive across systems.
- `mkFeatureRecipients` — the per-feature recipient map for re-key/rotate (`lib.nix`).
- `custom.host.exposed` + `exposedHostOffenders` — the exposed-host secret ban (`modules.nix`).
- `conformance/confinement.nix` — the structural-confinement proof (criterion 2).
- `examples/users/` — the reference user fleet (per-user shape); `examples/fleet/` — the reference host fleet.
