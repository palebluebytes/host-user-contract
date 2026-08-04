# ben/secrets/

Per-user secret storage for the secret-bearing reference user (ADR-0020).

A real `users` repo would keep ben's encrypted secrets here — e.g. `signing.yaml` holding the
commit-signing key — with a per-user `.sops.yaml` whose sole recipient is **ben's own key**. Because
each user's `secrets/` is encrypted to that user alone, co-locating several operator accounts in one
repo never lets one user decrypt another's secret.

No ciphertext is committed in this reference fleet: it would require real key material, and the
`signing` feature carries **no host recipients** (`features.signing` declares no `secretFiles`), so
nothing in the contract or the fleet reads this directory — the user's home module owns provisioning
(ADR-0001: "the secret rides the user's home sops, decrypted by the user's own key"). This file
documents the convention; a live repo replaces it with the encrypted secret and its `.sops.yaml`.
