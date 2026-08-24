{
  lib,
  pkgs,
  system,
  nixosSystem,
  # The contract's own flake outputs, and the kit behind them. The suite reads what each domain
  # needs off these rather than taking three dozen formals that `flake.nix` had to re-list — one
  # more place every new name had to be threaded through, and a place it could be forgotten.
  #
  # `self` rather than `kit` for everything public, deliberately: the domains below then exercise
  # the REAL flake outputs, so an output wired to the wrong kit attr fails the suite. `kit` is read
  # ONLY for `internal` — the in-repo kernels that are not outputs, including the `accountPlan` the
  # greeter also evaluates at login.
  self,
  kit,
}:
let
  contractModule = self.nixosModules.default;
  greeterModule = self.nixosModules.greeter;
  homeModule = self.homeModules.default;
  homeBaselineModule = self.homeModules.baseline;
  inherit (self)
    safeSet
    modes
    floorMode
    identitySchema
    greeterAffordances
    tier1EvalConfig
    featureGroups
    privilegedGroups
    ;
  inherit (self.lib)
    loadIdentity
    resolveIdentity
    mkHomeMatrix
    mkMembers
    enabledModesOf
    mkConfinementCheck
    mkIdentityPostureCheck
    mkHomeEvalCheck
    mkMemberChecks
    mkContractUser
    mkContractUsers
    mkContractFleet
    mkContractHome
    bindContractUser
    bindContractUsers
    renderNixConfig
    mkClaimReport
    ;
  inherit (kit.internal)
    diag
    featureNamesUnguarded
    floorUnguarded
    selectionUnguarded
    homeMatrixUnguarded
    bindModeUnguarded
    memberChecksUnguarded
    userOptions
    floorOf
    runsWith
    selectModeOver
    homeMatrixOver
    mkContractPackage
    mkContractPackageForHome
    bindContractPackage
    accountPlan
    writeManifest
    readManifest
    manifestFileName
    contractVersion
    versionsCompatible
    outOfUniverseProbes
    ;

  toolkit = import ./toolkit.nix {
    inherit
      lib
      contractModule
      homeModule
      userOptions
      nixosSystem
      resolveIdentity
      mkMembers
      floorMode
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
        modes
        featureGroups
        privilegedGroups
        ;
    })
    (import ./declaration.nix {
      inherit
        lib
        toolkit
        modes
        enabledModesOf
        mkMembers
        mkContractHome
        ;
    })
    (import ./confinement.nix {
      inherit
        lib
        pkgs
        toolkit
        mkConfinementCheck
        outOfUniverseProbes
        identitySchema
        ;
    })
    (import ./home-eval.nix {
      inherit
        lib
        pkgs
        mkHomeEvalCheck
        ;
    })
    (import ./modes.nix {
      inherit
        lib
        modes
        floorMode
        floorOf
        runsWith
        selectModeOver
        ;
    })
    (import ./home-matrix.nix {
      inherit
        lib
        modes
        homeMatrixOver
        mkHomeMatrix
        ;
    })
    (import ./members.nix {
      inherit
        lib
        toolkit
        loadIdentity
        mkMembers
        enabledModesOf
        ;
    })
    (import ./member-checks.nix {
      inherit
        lib
        pkgs
        toolkit
        mkMemberChecks
        ;
    })
    # The report every claim above is delivered THROUGH — including this domain's own. Its two
    # build-verdict directions are execution proofs, since a reporter's refusal lives in the
    # builder and no eval-time claim can reach it.
    (import ./claim-report.nix {
      inherit
        lib
        pkgs
        mkClaimReport
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
    (import ./greeter.nix {
      inherit
        lib
        pkgs
        toolkit
        greeterModule
        greeterAffordances
        runsWith
        safeSet
        tier1EvalConfig
        renderNixConfig
        ;
    })
    # The SHAPE of a refusal, proven at the constructor — the one place it can be, since `tryEval`
    # discards the message everywhere else in this suite (issue #64).
    (import ./diagnostics.nix { inherit lib diag; })
    # …and the other half: that the guards whose MESSAGE is the diagnosis fill that shape with the
    # right facts — the offenders named in the `problem` clause, never a count (issue #64).
    (import ./refusals.nix {
      inherit
        lib
        diag
        homeMatrixUnguarded
        selectionUnguarded
        bindModeUnguarded
        memberChecksUnguarded
        featureNamesUnguarded
        floorUnguarded
        ;
    })
    (import ./matrix.nix { inherit lib toolkit; })
    (import ./account-plan.nix { inherit lib floorMode accountPlan; })
    (import ./contract-package.nix {
      inherit
        lib
        pkgs
        toolkit
        mkContractPackage
        mkContractPackageForHome
        bindContractPackage
        writeManifest
        readManifest
        manifestFileName
        contractVersion
        versionsCompatible
        ;
    })
    (import ./contract-home.nix {
      inherit
        lib
        toolkit
        homeBaselineModule
        mkContractHome
        ;
    })
    (import ./contract-fleet.nix {
      inherit
        lib
        pkgs
        system
        toolkit
        mkContractFleet
        mkContractUsers
        ;
    })
    (import ./turnkey-bind.nix {
      inherit
        lib
        pkgs
        toolkit
        mkContractUser
        mkContractUsers
        bindContractUser
        bindContractUsers
        system
        ;
    })
  ];

  assertions = lib.concatMap (d: d.assertions) domains;
  # Execution-proof sub-derivations (e.g. the auth flow, the restricted-eval enforcement) become
  # the final runCommand's inputs, so building conformance builds them too.
  drvs = lib.foldl' (acc: d: acc // (d.drvs or { })) { } domains;

in
# Every claim above, and every execution proof beside it, delivered through the ONE report the check
# kit owns (issue #87). What used to sit here — the failure filter, the `ok`/`FAIL` rendering, the
# proofs section and the non-zero exit — was spelled out a second time in `examples/fleet/checks.nix`
# and a third time, differently, in the reference user fleet. The format had no owner, so the copies
# were free to drift and nothing would have caught it.
#
# Reached through `self.lib` like every other public name here, deliberately: the suite then reports
# through the REAL flake output a consumer gets, so a report wired to the wrong kit attr fails the
# suite rather than passing it quietly.
mkClaimReport {
  inherit pkgs;
  name = "contract-conformance";
  title = "contract conformance — synthetic users × the contract umbrella (no host repo)";
  claims = assertions;
  proofs = drvs;
}
