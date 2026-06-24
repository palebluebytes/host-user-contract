# Runtime provisioning is the shell-side realization: fully realize the account before the session

**Status:** Accepted; refines [ADR-0026](0026-greeter-seat-baseline-not-per-login-rebuild.md) (the greeter-seat baseline) and serves the portable-user north star (below).

Because a greeter user is **never built into the system** (ADR-0026 — no per-login rebuild), `realization.nix` — the module that maps a `custom.users.<u>`'s identity + grants to a full system account (`hashedPassword`, `authorizedKeys`, GECOS, the **clamped** safe declared groups + the grant groups) — **never runs for a greeter user**. `provision` is therefore the *only* thing that creates the account, yet today it does little more than `useradd`: the account ends up with **no password** (PAM lockout — a persisted Tier-1 user cannot unlock a screen locker or `su`), no SSH keys, no description, and none of the user's safe declared groups. That **breaks [ADR-0024](0024-greeter-is-a-contract-deliverable.md)'s promise** that a greeter-bound user realizes *identically* to a build-time one.

## Decision

`provision` is the **runtime, shell-side equivalent of `realization.nix`** for one user. Before starting the session it **fully realizes the account** from the (eval-free) `identity.json` + the safe-set grant:

- sets `hashedPassword` — the *same* hash `auth` already verified (so PAM works: screen-locker unlock, `su`);
- installs `authorizedKeys` from `sshKey` + `trustedKeys`;
- sets GECOS from `name`;
- adds the user's **safe declared groups** and enrolls the account in the **greeter-seat baseline** (the grant groups, ADR-0026);
- reproduces `realization.nix`'s **privileged-group clamp** in shell, so a hostile `identity.json` still cannot smuggle a privileged group at runtime.

Home activation **and** account realization both complete **before** the session starts.

## Why — the portable user (runtime north star)

The contract's runtime aim is a **portable user**: the *same* identity logs into *any* contract seat and gets the **exact same experience** — home config *and* allowed system-side options — with host and user mediated only by the contract. That demands the greeter fully realize both the home and the allowed system-side options before login, **identically on every seat**. A stub account that differs per host, or that locks the user out of PAM, defeats the whole point.

## Consequences

- `provision`'s signature gains the **identity source** (`identity.json` path) alongside `username` / `home` / `tier`.
- The clamp now lives in **two places** — `realization.nix` (build-time) and `provision` (runtime) — and both must enforce it. Conformance should test the **runtime** clamp exactly as it tests the build-time one, and treat **account-realization parity** (build-time vs runtime) as a target.

## Considered Options

- **Minimal account (username + home only)** — rejected: breaks realize-identically and causes PAM lockout of persisted users.
- **Per-login `nixos-rebuild` to run `realization.nix`** — rejected ([ADR-0026](0026-greeter-seat-baseline-not-per-login-rebuild.md)): global blast radius and declarative drift.
