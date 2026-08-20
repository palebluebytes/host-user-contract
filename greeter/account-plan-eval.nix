# contract-account-plan (issue #31 follow-up): the runtime evaluator that makes accountPlan the
# ONE owner of the account-combining rule. Before this, the greeter's `provision` re-spelled
# accountPlan's four-field fold (clamp ∪ grant, drop-empty-sshKey, gecos, pw) in jq, and the two
# spellings were reconciled only by booting `greeter-vm` and diffing field-for-field. That is the
# "necessarily expressed twice" claim issue #31 recorded — this overturns it: the rule now EXECUTES
# at login from its single Nix source, and `provision` becomes a pure renderer of the record this
# prints.
#
# It builds a small `contract-account-plan <identity.json> <grants.json> <mode>` tool that evaluates the
# contract's own pure `kit.internal.accountPlan` over the (authenticated) identity.json and prints
# the neutral account record as JSON. This is CONTRACT-OWNED code over ALREADY-AUTHENTICATED data,
# run AFTER the eval-free auth gate (ADR-0005 "data before code" governs the auth step, not this) —
# so it does not evaluate any USER Nix. It runs UNRESTRICTED: the Tier-1 restricted-eval posture
# (ADR-0019) is scoped to the home BUILD (the homeBuilder), never to provision, and this is a
# one-shot login computation, not a reproducible build — `--impure` is honest here (it reads a
# runtime path and the identity by env) and does not touch the user-code eval boundary.
#
# WHY it can single-source instead of codegen: `accountPlan` closes over `grantLib` (functions —
# non-serializable), so the applied function cannot be shipped. Instead the tool pins the contract
# SOURCE (`src`) + a nixpkgs `lib` source (`nixpkgsPath`) in-store and re-imports `kit` at runtime,
# reconstructing accountPlan (and grantLib, and the registry) from the ONE source — nothing is
# re-spelled. Identity defaulting is single-sourced too: the raw JSON is run through the real
# `identity.nix` submodule (the same option set the umbrella uses), so the optional-field defaults
# (`sshKey=""`, `trustedKeys=[]`, …) come from identity.nix, not a third hand-written place. An
# unknown/missing field throws — the same loud typo-net `loadIdentity` gives.
#
# INTERNAL, greeter-scoped: it needs `pkgs` (a package), which the pure kit (ADR-0002) does not
# have, so — like auth/provision/session — it is assembled inside the greeter module, the one place
# the contract ships packages (ADR-0017). The conformance suite imports it directly to prove the
# evaluator's record equals `accountPlan`'s.
{
  pkgs,
  # The contract source, pinned to the store so the runtime re-import needs no flake fetch (the
  # login already warmed the closure via `nix flake archive`). Shared with the mode-selection
  # evaluator through `./contract-source.nix`, which owns the filter.
  src ? import ./contract-source.nix { inherit pkgs; },
  # A nixpkgs `lib` source for the runtime eval. `pkgs.path` is the nixpkgs the seat already builds
  # with, so the record is computed under the same lib the build-time realization uses.
  nixpkgsPath ? pkgs.path,
}:
let
  # The evaluation, frozen to a store file (so the tool's `nix eval -f` imports a store path, not a
  # mutable one). `src`/`nixpkgsPath` interpolate to store paths at build time; the two runtime file
  # paths arrive via the environment (`--impure`), keeping this expression fully static. Only
  # `kit.internal.accountPlan` is forced, so the rest of the kit (realization, modules, the greeter
  # itself) stays a lazy thunk and is never imported at login.
  exprFile = pkgs.writeText "contract-account-plan.nix" ''
    let
      lib = import ${nixpkgsPath}/lib;
      kit = import ${src}/kit.nix { inherit lib; };
      # Default the raw identity.json through the REAL identity.nix submodule, so accountPlan gets a
      # resolved record (optional fields filled) and the defaults are single-sourced from identity.nix.
      rawIdentity = builtins.fromJSON (builtins.readFile (builtins.getEnv "CONTRACT_IDENTITY"));
      identity =
        (lib.evalModules {
          modules = [
            { options.identity = import ${src}/identity.nix { inherit lib; }; }
            { config.identity = rawIdentity; }
          ];
        }).config.identity;
      grants = builtins.fromJSON (builtins.readFile (builtins.getEnv "CONTRACT_GRANTS"));
      # The session shape this login was bound in — the greeter selected it one step earlier. It
      # decides which mode groups the account needs, and it is the reason a graphical login lands
      # in `input`/`uinput` without anything being granted.
      mode = builtins.getEnv "CONTRACT_MODE";
    in
    kit.internal.accountPlan { inherit identity grants mode; }
  '';
in
pkgs.writeShellApplication {
  name = "contract-account-plan";
  runtimeInputs = [ pkgs.nix ];
  text = ''
    identity=''${1:-}
    grants=''${2:-}
    mode=''${3:-}
    [ -n "$identity" ] && [ -n "$grants" ] && [ -n "$mode" ] || {
      echo "usage: contract-account-plan <identity.json> <grants.json> <mode>" >&2
      exit 1
    }
    [ -r "$identity" ] || { echo "contract-account-plan: cannot read identity '$identity'" >&2; exit 1; }
    [ -r "$grants" ] || { echo "contract-account-plan: cannot read grants '$grants'" >&2; exit 1; }

    # Evaluate the contract's own accountPlan over the identity + grant, print the record as JSON.
    # --impure: the two paths + the identity arrive at runtime (getEnv/readFile). nix-command: the
    # `nix eval` CLI. No flake ref is used, so no `flakes` feature and no network — src and the
    # nixpkgs lib are already in this tool's own closure.
    export CONTRACT_IDENTITY="$identity"
    export CONTRACT_GRANTS="$grants"
    export CONTRACT_MODE="$mode"
    exec nix eval --impure --json --extra-experimental-features nix-command -f ${exprFile}
  '';
}
