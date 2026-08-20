# The pre-built binding mode: the producer builds homes, the host activates them

**Status:** Accepted (2026-08-20). The seam between the two repos of
[0001](0001-host-user-contract.md).

The original binding evaluated the user's home module **inline**, inside the host's own NixOS build.
Two properties of that prompted the change:

1. **Eval-time attack surface.** The user's home ran under the host's eval context during
   `nixos-rebuild`. Nix evaluation is not a sandbox — a module body can trigger IFD, arbitrary
   fetches, or non-termination. For an operator who has not read every commit of every user's home,
   that is a latent risk on the *build-time* path, where it is least expected.
2. **Host-controlled package versions.** Following the host's nixpkgs let the host force security
   patches but removed the user's control of their own versions. The insight that settled it:
   **packages are only advisory when the user has daemon access** — a user with the daemon socket
   can `nix shell nixpkgs#anything` regardless of what their home declares. Since host control was
   never enforceable, the user owning their versions is the coherent position rather than a
   trade-off.

The runtime greeter path already operated on a pre-built output. This makes the build-time path
match.

## Decision

**A users repo publishes built artifacts; a host pins, reads and activates them.**

- The producer publishes a **contractPackage** per user per mode: a derivation whose `$out` holds
  the home's `activate` script and a `contract-manifest.json`.
- The host reads the manifest at eval time with a plain `importJSON`. The package is a pinned flake
  input, already in the store, so this is **not IFD**.
- After the host's switch, a privileged activation step runs `$contractPackage/activate`.

**The host never evaluates a line of the user's Nix.** Content-addressing means the host's lock pin
covers the activation and the manifest atomically — they cannot drift — and accepting a new home
version is an explicit lock update.

## Trade-offs accepted

- **A host can no longer force security patches on a user's packages.** A nixpkgs CVE is patched by
  the user updating their own pin. Mitigated operationally by the user's CI automating flake
  updates; documented as a required discipline, not a structural guarantee.
- **`home-manager rollback` is replaced by pinning.** The user's git history is the generation log;
  rollback is re-pinning to an earlier build. Strictly better in one respect — the host operator can
  do it unilaterally as long as the cache retains the build — and worse in another: there are no
  per-host generation links.
- **The one-nixpkgs invariant is relaxed.** A pre-built user owns their pin. The base closure is
  still shared when the user's nixpkgs follows the host's; only overlaid packages rebuild.

## Consequences

- **The two binding paths converge.** A greeter and a build-time bind now share one model — consume
  a pre-built store path, activate it — where before they were inline-eval and shell-side provision.
- **The producer's overlays stay sandboxed.** An overlay is `nixpkgs → nixpkgs`, i.e. arbitrary
  code; it materializes only in the user's own home build, never in the host's system `pkgs`.
- **IFD is banned throughout, and that is load-bearing elsewhere.** It is what closes the
  auto-classification route in [0023](0023-no-classification-of-home-content.md).

## Considered alternatives

- **Keep inline eval for hosts that want hard package enforcement** — retained for a while, then
  deleted with zero callers. Its stated value was that the host evaluates the home live, so a denied
  program cannot be present; but package restriction was never host-enforceable with daemon access
  ([0016](0016-program-scope.md)), which is precisely *why* pre-built is the coherent choice. System
  effects — groups, privilege — are controlled equally well by the pre-built path.
- **Let the host build the user's home from source at switch time** — rejected: it reintroduces
  user-Nix evaluation on the host, which is the thing being removed.
