# The contract's OWN conformance suite (ADR-0020 Q5): proves the contract's promises in
# ISOLATION — synthetic manifests bound on synthetic systems built from the contract
# umbrella + bare nixpkgs, with no host repo, no real user, and no host bindings. This is
# what gives the contract independent CI and protects it for every consumer.
#
# Because the display *backend* is a host binding (the contract only decides), this suite
# asserts the session-union DECISION (custom.gui.surface), not SDDM/Plasma. The rendering
# test (the gui-union VM) and the real-fleet coherence gate stay in the host repo.
#
# Structure: ./toolkit.nix builds the shared synthetic-world fixtures once; each domain file
# (./realization.nix, ./requests.nix, ./bind.nix, ./greeter.nix, ./matrix.nix) is a focused list
# of `{ name; ok; }` claims (+ optional `drvs` for execution proofs). This file just aggregates
# them: concat the assertions, merge the drvs (so they build), render the report, gate the build.
{
  lib,
  pkgs,
  contractModule,
  greeterModule,
  homeModule,
  homeGreeterDesktopModule,
  safeSet,
  greeterGrants,
  tier1EvalConfig,
  renderNixConfig,
  featureGroups,
  privilegedGroups,
  loadIdentity,
  bindUser,
  bindUserModule,
  nixosSystem,
  system,
}:
let
  toolkit = import ./toolkit.nix {
    inherit
      lib
      contractModule
      homeModule
      nixosSystem
      loadIdentity
      system
      ;
  };

  domains = [
    (import ./realization.nix {
      inherit
        lib
        toolkit
        loadIdentity
        safeSet
        featureGroups
        privilegedGroups
        ;
    })
    (import ./requests.nix {
      inherit
        lib
        toolkit
        homeModule
        homeGreeterDesktopModule
        ;
    })
    (import ./bind.nix {
      inherit
        toolkit
        bindUser
        bindUserModule
        greeterGrants
        ;
    })
    (import ./greeter.nix {
      inherit
        lib
        pkgs
        toolkit
        greeterModule
        greeterGrants
        safeSet
        tier1EvalConfig
        renderNixConfig
        ;
    })
    (import ./matrix.nix { inherit lib toolkit; })
  ];

  assertions = lib.concatMap (d: d.assertions) domains;
  # Execution-proof sub-derivations (e.g. the auth flow, the restricted-eval enforcement) become
  # the final runCommand's inputs, so building conformance builds them too.
  drvs = lib.foldl' (acc: d: acc // (d.drvs or { })) { } domains;

  failures = builtins.filter (a: !a.ok) assertions;
  report = lib.concatMapStringsSep "\n" (
    a: "  ${if a.ok then "ok  " else "FAIL"}  ${a.name}"
  ) assertions;
in
pkgs.runCommand "contract-conformance" drvs ''
  cat <<'EOF'
  contract conformance — synthetic users × the contract umbrella (no host repo):
  ${report}

  execution proofs (built ⇒ ok):
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "  ${n}: ${v}") drvs)}
  EOF
  ${lib.optionalString (failures != [ ]) ''
    echo "contract conformance FAILED (see above)" >&2
    exit 1
  ''}
  touch $out
''
