# Pre-built binding mode: user CI produces `contractPackage`; the host pins, reads, and activates it

**Status:** Proposed. Amends [ADR-0023](0023-user-flake-shape.md) (user flake shape gains
`packages.${system}.contractPackage`); amends [ADR-0018](0018-user-confinement-manifest-greeter.md)
(`execPayload` deferred); related to [ADR-0033](0033-daemon-restricted-user-package-policy.md).

[ADR-0023](0023-user-flake-shape.md) fixed the user flake shape and `bindUserModule` as the
real binding mechanism: the host imports the user's home module into `home-manager.users.<u>`
and evaluates it inline as part of its own NixOS build. Two properties of this model prompted
reconsideration:

1. **Eval-time attack surface.** The user's home module runs under the host's eval context
   during `nixos-rebuild`. Nix evaluation is not a sandbox — a module body can trigger
   `builtins.fetch*`, IFD, or non-termination; for an operator who has not read every commit
   of every user's home, this is a latent risk.
2. **Host-controlled package versions.** `inputs.nixpkgs.follows` builds the user's home
   against the host's nixpkgs. This gives the host the ability to force security patches but
   removes the user's control over their own package versions. The insight that resolved this:
   **packages are always advisory when the user has Nix daemon access** — a user with the
   daemon socket can `nix shell nixpkgs#<anything>` regardless of what their home declares.
   Since host-controlled packages were never enforceable, the user should own their versions.

The greeter runtime path already operates on a pre-built output: `homeBuilder` evaluates and
builds the home, and `provision` activates the resulting store path. The pre-built binding
mode makes the build-time path match.

## Decision

### 1. The user flake gains `packages.${system}.contractPackage`

A new required output alongside `identity.json` and the home module (ADR-0023). It is a
content-addressed derivation produced by the contract's `mkContractPackage` lib function:

```nix
packages.${system}.contractPackage =
  contractLib.mkContractPackage {
    activationPackage = homeConfig.activationPackage;
    requests          = homeConfig.config.contract.requests;
    packages          = homeConfig.config.home.packages;  # top-level package names
    username          = "inkpotmonkey";
  };
```

The derivation's `$out` contains:

```
$out/
  activate                 # the home activation script
  contract-requests.json   # feature requests + package manifest
```

`contract-requests.json` schema:

```json
{
  "version": 1,
  "username": "inkpotmonkey",
  "requests": {
    "gui": { "session": "wayland", "desktop": "plasma" }
  },
  "packages": ["firefox", "vim", "git"]
}
```

Content-addressing means the host's flake.lock pin covers both the activation and the
requests atomically — they cannot drift.

### 2. The host reads `contract-requests.json` at eval time (no IFD)

`contractPackage` is a pinned flake input, already in the store before the host evaluates.
Reading `contract-requests.json` from it is a plain `lib.importJSON` — not IFD. The host
bridges feature requests into feature configuration exactly as `bindUserModule` does today.

### 3. The host activates at switch time

After the host's NixOS switch, a privileged activation step (a system activation script or
a `provision`-style service) runs `$contractPackage/activate` and then replaces `~/.nix-profile`
with a host-built package profile (see ADR-0033). The user's session starts with the full
home config and the host-approved package set.

### 4. `bindUserModule` is retained for inline-eval (hard-enforcement) deployments

The two binding modes are explicit design choices with documented ceilings:

| Mode | Mechanism | Package ownership | Program enforcement |
|---|---|---|---|
| Pre-built | `contractPackage` pin | User (user CI) | Soft (PATH + host profile) |
| Inline eval | `bindUserModule` | Host (host nixpkgs) | Hard (filtered `pkgs`) |

Hosts that require hard package enforcement — where the host must control which programs are
even buildable — use the inline-eval mode. The contract supports both. The greeter runtime
path is always pre-built.

### 5. `execPayload` is deferred

The `execPayload` registry field and its exclusion from `runtimeEligibleFeature` are removed
from the beta. No feature carries a host-executed user payload yet; the mechanism re-enters
when a concrete feature (such as `kanata-with-cmd`) is designed. The exec-payload *concept*
(a request payload the host executes with system privilege is a code-exec vector, never
safe-set-eligible) remains in the model — only the flag and its derivation step are deferred.

## Why

- **Eliminates user-Nix eval at host build time.** The host never evaluates the user's home
  module. It activates a pre-built store path. The eval-time attack surface disappears.
- **Content-addressed pin = tamper detection.** The host explicitly updates its flake.lock
  when accepting a new home version; the hash verifies integrity.
- **User owns their packages.** Since packages were always advisory under daemon access, the
  user carrying their own tested versions is the coherent position, not a trade-off.
- **Stronger "one mechanism, both paths."** The runtime greeter and the build-time path now
  share the same model: consume a pre-built store path, activate it. Today they diverge
  (inline eval vs shell-side provision).
- **Generation history belongs to CI artifacts.** The user's git history is the generation
  log; rollback = re-pin `contractPackage` to an earlier store hash. The host operator can
  do this unilaterally as long as the binary cache retains old builds — strictly better
  than `home-manager rollback`, which requires the previous generation on the local host.

## Trade-offs accepted

- **Host can no longer force security patches on user packages.** A nixpkgs CVE is patched
  by the fleet operator bumping the host's nixpkgs; in the pre-built mode the user's home
  still builds against the user's own pin until the user updates it. Mitigated operationally
  by user CI automating `nix flake update` on a schedule. Documented as a required operational
  discipline, not a structural guarantee.
- **`inputs.nixpkgs.follows` invariant is relaxed** for pre-built users. The one-nixpkgs
  invariant (ADR-0023) holds for the inline-eval mode; pre-built users own their pin.
- **`home-manager rollback` is replaced by CI artifact pinning.** No per-host generation
  links; the user's CI build history is the rollback path.

## Consequences

- The contract `lib` gains `mkContractPackage`. No new NixOS module or package dependency —
  the function is a pure derivation wrapper over an already-evaluated home. The package-free
  invariant (ADR-0020) holds.
- The user flake shape (ADR-0023) grows one required output. User repos must add it; the
  contract documents the `mkContractPackage` call as the standard wiring.
- The conformance suite gains a test for the pre-built path: pin a minimal `contractPackage`,
  have the host read its requests and activate it, assert the same realized account as the
  inline-eval path produces.
