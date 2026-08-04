# The contract handles no secrets beyond the login credential

**Status:** Accepted (2026-08-04). Supersedes [ADR-0005](0005-platform-backend-agnostic-secrets.md) (the platform secret-provisioning interface) and [ADR-0015](0015-greeter-secret-provisioning.md) (greeter secret provisioning); retires the secret-bearing threat-model mechanisms of [ADR-0001](0001-host-user-contract.md) (the `secretBearing`/`secretFiles` metadata, `recipients-from-grants`, and the exposed-host ban).

The contract accumulated three distinct secret subsystems, and each turned out to be either dormant plumbing or a responsibility that does not belong to the contract:

1. **Feature secrets** — the `signing` feature plus the `secretBearing`/`secretFiles` metadata, `mkFeatureRecipients` (recipients-from-grants), and the exposed-host ban (ADR-0001). `signing` was the *only* secret-bearing feature, and even it never used the recipient machinery — its secret rode the user's **own** home sops, decrypted by the user's **own** key. So `mkFeatureRecipients` returned `{}` over every real fleet, and the exposed-host ban had nothing to ban.
2. **The platform secret-provisioning interface** — `custom.platform` (ADR-0005). Declared and stubbed everywhere, **consumed by nothing**: no feature ever declared a logical secret or read a resolved path.
3. **Greeter secret provisioning** — unlocking the user's own age key at a roaming login so their home sops decrypt (ADR-0015). This is the user's own key for the user's own home; the contract does not own or re-key it, and making it available is not the contract's job.

## Decision

**The contract handles no secrets beyond the login credential.** The only secret it touches is the **hashedPassword** the greeter authenticates on and the realization installs — one of the three tiers of "user secret" (public identity / hashedPassword / feature secret, ADR-0001). Everything else is removed:

- The `signing` feature and the `secretBearing`/`secretFiles` per-entry registry fields.
- `mkFeatureRecipients` (recipient derivation) and `exposedHostOffenders` (the exposed-host ban predicate + its NixOS assertion). `custom.host.exposed` survives as a **plain host fact** a home may read via `hostFacts`; the contract enforces nothing on it.
- The `custom.platform` secret-provisioning interface (`platform.nix`) and every host/VM stub of it.
- Greeter secret provisioning: the `secretProvisioning` options, the `contract-greeter-unlock` and `contract-greeter-secret-key` scripts, the escrow keyFetcher seam, and the reference escrow keyserver. The greeter still authenticates on the password and activates the home — now **always secret-free**.

A user's own feature secrets (a commit-signing key, API tokens, git-annex, …) remain entirely the **user's own home** concern: they ride the user's own key, provisioned by the user's own home module, and never pass through the contract. A host is never a recipient of a user's secret.

## Consequences

- **The self-contained-user invariant is now structural, not conventional.** Previously the only thing keeping a user's secret out of the host-recipient path was the convention that user-secret features declined to declare `secretFiles`. With the whole mechanism gone, a host **cannot** become a recipient of any user secret — there is no vocabulary to express it.
- **Host Tier-1 signing authority (ADR-0011) is untouched.** That is the host signing/verifying a user repo for authenticity — repo authentication, not a user secret. It stays.
- **A roaming Tier-1 user gets a clean, secret-free session** at any seat (the ADR-0006 Q4 graceful-degradation baseline), and nothing more. Recovering their home secrets at a foreign seat is out of scope for the contract; a user who needs it provisions their key by their own means.
- **ADR-0005 and ADR-0015 are superseded in full.** ADR-0001 remains the foundational record but its secret-bearing mechanisms (mechanic 6's secrets accessor, `recipients-from-grants`, revocation-as-remove-recipient, the exposed-host ban) are retired by this ADR; read them as history.

## Considered Options

- **Keep the mechanisms dormant** (test the recipient algorithm, keep the platform seam for a future feature) — rejected: it leaves security-relevant machinery unexercised and, worse, keeps open the structural possibility of a host becoming a recipient of a user secret. The invariant is stronger when the vocabulary does not exist.
- **Keep greeter secret provisioning** (it is the user's own key, not a host secret) — rejected: the contract shipping the *step* is still the contract taking on secret handling; the user's key recovery is the user's own concern.
- **Remove all three (chosen)** — the contract's surface is exactly: identity (incl. hashedPassword), grants, non-secret feature configuration, and the greeter's password-authenticated, secret-free activation.

## If secrets return

This decision is reversible, and deliberately so. Nothing here forecloses secret handling; it removes machinery that was dormant or misplaced. A future need should re-open the question rather than route around it.

**The gate is this ADR, not the code.** The implementation is recoverable from git history (the pre-removal tree: the recipient derivation and `featureMeta` in `lib.nix`/`kit.nix`, the `custom.platform` interface in `platform.nix`, the greeter `unlock`/`secret-key` scripts, and the `examples/escrow-keyserver` reference). What a return costs is a **new ADR that supersedes this one** and consciously loosens the "no secrets / self-contained-user" principle — a decision, not a refactor.

**The three subsystems return independently, with different justifications:**

1. **Host/fleet-shared secrets** (the `secretFiles` → recipients-from-grants model) — the lightest, least controversial return: a secret *owned by the host/fleet* (a machine cert, a shared deploy key), not by any user. It does not touch the user-secret invariant. Expect this one first, if any.
2. **Greeter secret provisioning** (the user's *own* key made available at a roaming seat, ADR-0015) — recoverable, but the most value-laden: the contract shipping the *step* is the contested part, not the ownership.
3. **The platform secret interface** (ADR-0005) — trivially re-addable, but only once something in (1) or (2) actually consumes it. Its original flaw was existing with no consumer; do not re-add it speculatively.

**Do not restore the old design verbatim — fix its sharp edge.** The pre-removal design used one word, `secretBearing`, to cover both host-owned shared secrets and user-owned secrets, with only *convention* (a user-secret feature declining to declare `secretFiles`) keeping a user's secret out of the host-recipient path. A clean return gives **host-domain and user-domain secrets distinct vocabulary** so a host can never become a recipient of a user secret **by construction**, not by discipline — making structural what is, after this ADR, merely absent.
