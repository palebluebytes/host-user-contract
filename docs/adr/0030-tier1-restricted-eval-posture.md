# The contract pins the Tier-1 restricted-eval posture; the greeter applies it, the repo cannot widen it

**Status:** Accepted; completes [ADR-0022](0022-anyhost-greeter-runtime-binding.md) step 5/6 (the home build) and applies [ADR-0027](0027-host-is-sole-tier1-signing-authority.md)'s "a repo cannot self-certify" to *evaluation*.

The greeter authenticates **eval-free** on inert data (ADR-0022 "data before code") and only *then* evaluates and builds the user's home (step 5/6). But "evaluate + build under restricted eval" was, until now, only **prose** — a promise in the `homeBuilder` option doc, with **nothing pinned and nothing enforced**. The eval posture was entirely the host's to invent, so two seats running the same signed repo could evaluate it under wildly different rules, and — worse — **the repo could widen its own eval**: a flake's `nixConfig` (`allow-import-from-derivation = true`, extra substituters, relaxed flags) would be honoured, letting a Tier-1 repo relax the very settings meant to contain it. That is exactly the self-certification ADR-0027 forbids for *tier classification*, here leaking back in through *eval policy*.

Tier 1 is **vouched-for** by the host's signature, not blindly trusted (ADR-0027). A signed-but-careless (or signed-then-compromised) repo should still not be able to read `/etc/shadow` at eval time, trigger arbitrary builds via IFD, or escape the build sandbox — and it must never be able to *turn those guards off itself*.

## Decision

The **contract pins** the Tier-1 eval posture as canonical data (`tier1EvalConfig`, a projection beside `safeSet`/`greeterGrants`); the **greeter applies** it; the **repo cannot widen** it. As `nix.conf`:

- `accept-flake-config = false` — **the un-widenable linchpin**: the repo's own `nixConfig` is ignored, so it cannot relax any setting below by self-declaration (ADR-0027 applied to eval).
- `restrict-eval = true` — eval may touch only the store + allowed paths/URIs: no `builtins.readFile "/etc/shadow"`, no arbitrary eval-time fetch.
- `allow-import-from-derivation = false` — no IFD: eval cannot force a build and import its output.
- `sandbox = true` — the build itself runs isolated (no network, no host filesystem).

The greeter renders this (the contract's own `renderNixConfig`, single-sourced) and hands it to the host's `homeBuilder` as **`NIX_CONFIG`**, which *augments* the seat's `/etc/nix/nix.conf` (so `experimental-features` etc. survive) — a naive `nix build` binding inherits the floor for free. A host may **add** restrictions in its `homeBuilder`; it cannot remove these.

`restrict-eval` would break an offline build that still needs to fetch its locked inputs, so the **fetch step is upgraded** from `nix flake prefetch` (source only) to `nix flake archive` (source **+ the whole input closure**), run *before* auth with `accept-flake-config = false`. By the time the restricted build runs, every locked input is already a store path — no eval-time network is needed, and the "fetch as data, then build restricted" ordering mirrors "authenticate as data, then run code".

## Consequences

- `tier1EvalConfig` joins the public data surface (flake output + `self.lib.renderNixConfig`); the greeter exposes a **read-only** `custom.greeter.tier1EvalConfig` for operator audit, fixed to the contract value exactly as `grants` is fixed to `greeterGrants`.
- Conformance proves it two ways: **eval assertions** (the posture carries the four settings; the rendered `NIX_CONFIG` carries them verbatim; the greeter exposes the unwidenable value), and an **executable proof** — the rendered posture, applied via `NIX_CONFIG`, actually blocks a hostile `builtins.readFile` of a host file, where the same eval succeeds without it (the control). The proof runs `nix-instantiate --eval` inside a build sandbox, so no heavy VM is needed.
- The clamp now has a sibling guard at a *third* layer: identity input is clamped (realization/provision), grants are bounded to the safe set, and now **eval itself** is bounded. Defence in depth, each independent.
- **Tier 2** (untrusted/ephemeral) will pin a *stricter* posture (e.g. no network at all, tighter allowed-uris); the data shape (`tierNEvalConfig`) generalises, but tier 2 stays **deferred** (the provisioning helper still refuses it, ADR-0022).

## Considered Options

- **Leave the posture to the host (status quo)** — rejected: no canonical floor, no enforcement, and the repo could widen its own eval via `nixConfig` — the ADR-0027 hole.
- **Keep `nix flake prefetch` + `restrict-eval`** — rejected: the restricted build cannot fetch locked inputs, so legitimate homes fail to build. Warming the closure with `nix flake archive` first is what makes restricted eval coherent.
- **A reference `homeBuilder` that enforces the posture itself** — rejected: building needs home-manager, which the contract does not ship (ADR-0020). Pinning the posture as data + exporting it as `NIX_CONFIG` keeps the contract package-free while still delivering the floor to whatever builder the host binds.
- **Trust Tier 1 fully (no restricted eval)** — rejected: a host *signature* vouches for provenance, not for the repo being free of accidents or later compromise; the floor is cheap insurance (ADR-0027's spirit).
