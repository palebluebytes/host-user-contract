# The contract handles no secrets beyond the login credential

**Status:** Accepted (2026-08-20). Constrains everything the contract may ever carry.

The contract once had three secret subsystems, and each turned out to be dormant plumbing or a
responsibility that does not belong to it:

1. **Feature secrets** — per-feature secret metadata, a recipients-from-grants derivation, and an
   exposed-host ban. Exactly one feature was ever secret-bearing, and even it did not use the
   machinery: its secret rode the user's own home sops, decrypted by the user's own key. The
   recipient derivation returned `{}` over every real fleet and the ban had nothing to ban.
2. **A platform secret-provisioning interface** — declared and stubbed everywhere, **consumed by
   nothing**. No feature ever declared a logical secret or read a resolved path.
3. **Greeter secret provisioning** — unlocking a roaming user's own key at login so their home sops
   decrypt. That is the user's own key for the user's own home.

## Decision

**The only secret the contract touches is the `hashedPassword` a greeter authenticates on and the
realization installs.** Everything else is gone: no secret-bearing features, no recipient
derivation, no platform secret interface, no greeter unlock step.

A user's own secrets — a signing key, API tokens — are entirely the **user's own home** concern.
They ride the user's own key, provisioned by the user's own home module, and never pass through the
contract. **A host is never a recipient of a user's secret.**

## Consequences

- **The self-contained-user invariant becomes structural rather than conventional.** Before, the
  only thing keeping a user's secret off the host-recipient path was the convention that
  user-secret features declined to declare one. With the vocabulary deleted, a host **cannot**
  become a recipient — there is no way to express it.
- **`contract.exposed` survives as a plain host fact** an operator records. The contract enforces
  nothing on it.
- **A roaming user gets a clean, secret-free session** at any seat. Recovering their own home
  secrets at a foreign seat is out of scope; a user who needs it provisions their key by their own
  means.

## If secrets return

Deliberately reversible. Nothing here forecloses secret handling; it removes machinery that was
dormant or misplaced. **The gate is this record, not the code** — the implementation is recoverable
from git history, and what a return costs is a new record superseding this one and consciously
loosening the self-contained-user principle. A decision, not a refactor.

The three subsystems return independently and with different justifications. **Host-owned secrets**
(a machine cert, a shared deploy key) are the lightest: they do not touch the user-secret invariant
and are the one to expect first. **Greeter secret provisioning** is the most value-laden — the
contested part is the contract shipping the *step*, not who owns the key. **A platform secret
interface** is trivially re-addable but only once something else consumes it; its original defect
was existing with no consumer.

**Do not restore the old design verbatim.** It used one word for both host-owned and user-owned
secrets, with only convention keeping a user's secret out of the host-recipient path. A clean
return gives the two domains distinct vocabulary, so the invariant holds by construction rather
than by discipline.

## Considered alternatives

- **Keep the mechanisms dormant** for a future feature — rejected: unexercised security machinery,
  and it keeps open the structural possibility this record closes. The invariant is stronger when
  the vocabulary does not exist.
- **Keep greeter secret provisioning** on the grounds that it is the user's own key — rejected: the
  contract shipping the step is still the contract taking on secret handling.
