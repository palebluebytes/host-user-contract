# The contract's OWN conformance suite (ADR-0004 Q5): proves the contract's promises in
# ISOLATION — synthetic manifests bound on synthetic systems built from the contract
# umbrella + bare nixpkgs, with no host repo, no real user, and no host bindings. This is
# what gives the contract independent CI and protects it for every consumer.
#
# Because the display *backend* is a host binding (the contract only decides), this suite
# asserts the session-agnostic gui-surface DECISION (custom.gui.surface.enabled), not SDDM/Plasma;
# the session type is the seat's concern (ADR-0021). The rendering test (the gui-surface VM) and
# the real-fleet coherence gate stay in the host repo.
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
  homeBaselineModule,
  safeSet,
  variantAxes,
  variants,
  bakeMatrixOver,
  hostFactsFor,
  greeterGrants,
  tier1EvalConfig,
  renderNixConfig,
  featureGroups,
  privilegedGroups,
  loadIdentity,
  mkBakeMatrix,
  mkContractRoster,
  traceUser,
  mkConfinementCheck,
  mkIdentityPostureCheck,
  mkVariantEvalCheck,
  outOfUniverseProbes,
  mkContractUser,
  mkContractUsers,
  mkContractHome,
  bindContractUser,
  mkContractPackage,
  mkContractPackageForHome,
  bindContractPackage,
  accountPlan,
  writeManifest,
  readManifest,
  manifestFileName,
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
        variantAxes
        variants
        hostFactsFor
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
        safeSet
        ;
    })
    (import ./confinement.nix {
      inherit
        lib
        pkgs
        toolkit
        mkConfinementCheck
        outOfUniverseProbes
        ;
    })
    (import ./variant-eval.nix {
      inherit
        lib
        pkgs
        mkVariantEvalCheck
        ;
    })
    (import ./bake-matrix.nix {
      inherit
        lib
        variants
        bakeMatrixOver
        mkBakeMatrix
        ;
    })
    (import ./roster.nix {
      inherit
        lib
        loadIdentity
        mkContractRoster
        ;
    })
    (import ./identity-posture.nix {
      inherit
        lib
        pkgs
        toolkit
        loadIdentity
        mkIdentityPostureCheck
        ;
    })
    (import ./bind.nix {
      inherit
        toolkit
        traceUser
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
    (import ./account-plan.nix { inherit lib accountPlan; })
    (import ./contract-package.nix {
      inherit
        pkgs
        toolkit
        mkContractPackage
        mkContractPackageForHome
        bindContractPackage
        writeManifest
        readManifest
        manifestFileName
        greeterGrants
        ;
    })
    (import ./contract-home.nix {
      inherit
        lib
        homeGreeterDesktopModule
        homeBaselineModule
        mkContractHome
        ;
    })
    (import ./turnkey-bind.nix {
      inherit
        lib
        pkgs
        toolkit
        loadIdentity
        mkContractUser
        mkContractUsers
        bindContractUser
        system
        ;
    })
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
