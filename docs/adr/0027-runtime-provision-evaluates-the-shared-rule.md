# Runtime provision evaluates the shared `accountPlan`, not a re-spelling of it

**Status:** Accepted (2026-08-07). Extends [ADR-0012](0012-runtime-provisioning-is-shell-side-realization.md) (runtime provisioning is the shell-side realization) and completes the account-plan arc begun in issues #30/#31 ([`accountPlan`](../../account-plan.nix), [`grantLib`](../../kit.nix) of issue #28). It **overturns** issue #31's recorded claim that the account-combining rule "is *necessarily* expressed twice."

Issues #30/#31 introduced `accountPlan` — the single pure `(identity, grants) → account record` — as the description **both** realization adapters render: the build-time [`realization.nix`](../../realization.nix) maps it into `users.users`, and the runtime greeter [`provision`](../../greeter/provision.nix) realizes it shell-side (ADR-0012, because a greeter user is never built into the system, ADR-0010). But the runtime side only *reproduced* the rule: `provision` re-spelled `accountPlan`'s four-field fold (the privileged-group clamp ∪ the grant groups, drop-empty-`sshKey`, GECOS, the password) in `jq`. Only the rule's *inputs* were single-sourced — the clamp **set** and the identity **field names**, baked into a `provisionPlan` the shell read. The **rule itself** lived in two languages.

## What the duplication cost

- **The rule had two owners.** A change to the fold — a new account field, a reordering, a new clamp — had to land in Nix *and* in the `jq`, or the two silently diverged.
- **The compiler could not see across the boundary.** The two spellings were reconciled only by an assertion in the [`greeter-provision` VM](../../conformance/greeter-vm.nix) that boots a machine and diffs the realized account against the build-time record field-for-field. Every branch of the `jq` needed its own drift-guard: issue #31's own last step was adding a second `nokey` fixture to that VM solely because the `jq`'s empty-`sshKey` branch was otherwise unexercised.
- **The claim it rested on was false.** The comments justified the `jq` as unavoidable — "a shell login cannot call the Nix function." But `provision` runs **after** the eval-free auth gate and **after** the greeter has already run `nix flake archive` + the home `nix build`; Nix is in hand, and `provision` runs *unrestricted* (the Tier-1 posture, ADR-0014, is scoped to the home build, never to `provision`).

## Decision

`provision` **evaluates** the one `accountPlan` at login instead of reproducing it. The contract ships a small internal, greeter-scoped tool — [`contract-account-plan`](../../greeter/account-plan-eval.nix) — that pins the contract source + a nixpkgs `lib` in-store, re-imports `kit.internal.accountPlan`, and prints the neutral record as JSON for a given `identity.json` + grant set. `provision` becomes a **pure renderer**: it execs the tool and writes GECOS, the password, `authorizedKeys`, and the groups; it owns no combining logic.

- **One textual source.** The fold exists once, in `accountPlan`. `provision` holds none of it. Because `accountPlan` closes over `grantLib` (functions, non-serializable), the tool reconstructs it *from source* at runtime rather than shipping an applied function or a generated shell — so `grantLib`, the registry, and the clamp are all the single source too, nothing re-spelled.
- **Identity defaulting single-sources through `identity.nix`.** The raw `identity.json` is run through the real identity submodule, so the optional-field defaults (`sshKey = ""`, `trustedKeys = [ ]`, …) — previously the `jq`'s `// ""` / `// []` fallbacks — come from `identity.nix`. An unknown/missing field throws, the same loud typo-net `loadIdentity` gives.
- **`--impure`, and that is honest.** The tool reads a runtime path and the identity by environment, so the eval is impure. It is **contract-owned code over already-authenticated data**, run after the auth gate — it evaluates no user Nix, and it does not touch the ADR-0006 "data before code" boundary or the ADR-0014 user-code eval posture. It is a one-shot login computation, not a reproducible build, so purity buys nothing here.
- **Fail-closed.** If the evaluation fails (a malformed identity that slipped past auth, a contract bug), `provision` aborts before touching the account — no half-realized login.

The seat marker stays out of the rule: `accountPlan` remains the **seat-agnostic portable account**; `provision` adds the `greeter-users` marker (the one group a build-time user never gets, ADR-0010) on the render side.

## Consequences

- **The clamp rule is proven without a boot.** Its guarantees — the privileged-group clamp, the empty-`sshKey` drop, key ordering — move to a pure eval domain, [`conformance/account-plan.nix`](../../conformance/account-plan.nix), driving `accountPlan` directly. The `greeter-provision` VM's job narrows to proving the **renderer** surfaces the record faithfully; its second `nokey` fixture is retired (the branch is now pure-proven).
- **`provisionPlan` dissolves.** `provision` no longer needs the clamp set or the identity field-name projection — the tool owns them. Only the seat groups (baseline ∪ the `greeter-users` marker) remain render-side.
- **A per-login `nix eval`.** Each login runs one pure eval — no network (the closure is already warmed by `flake archive`), sub-second against a path that already does `flake archive` + a home `nix build`. `provision` gains `nix` (via the tool) in its runtime inputs, and the seat closure gains the pinned contract source + a nixpkgs `lib` source.
- **The interface is the test surface.** `accountPlan` is now genuinely the single description both adapters render; verifying the rule no longer means running two encodings and diffing.

The mechanism-vs-binding split (ADR-0008) is preserved: the account rule is core *mechanism*, and the evaluator is a contract-shipped reference program — a seat does not get to redefine how an identity and a grant become an account.
