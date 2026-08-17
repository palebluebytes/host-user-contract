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
  # ONLY for `internal` — the in-repo kernels that are not outputs (ADR-0026), including the
  # `accountPlan` the greeter also evaluates at login.
  self,
  kit,
}:
let
  contractModule = self.nixosModules.default;
  greeterModule = self.nixosModules.greeter;
  homeModule = self.homeModules.default;
  homeGreeterDesktopModule = self.homeModules.greeterDesktop;
  homeBaselineModule = self.homeModules.baseline;
  inherit (self)
    safeSet
    homes
    greeterGrants
    tier1EvalConfig
    featureGroups
    privilegedGroups
    ;
  inherit (self.lib)
    loadIdentity
    mkHomeMatrix
    mkMembers
    traceUser
    mkConfinementCheck
    mkIdentityPostureCheck
    mkHomeEvalCheck
    mkMemberChecks
    mkContractUser
    mkContractUsers
    mkContractHome
    bindContractUser
    renderNixConfig
    hostFactsFor
    ;
  inherit (kit.internal)
    homeAxes
    homeMatrixOver
    mkContractPackage
    mkContractPackageForHome
    bindContractPackage
    accountPlan
    writeManifest
    readManifest
    manifestFileName
    outOfUniverseProbes
    ;

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
        homeAxes
        homes
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
    (import ./home-eval.nix {
      inherit
        lib
        pkgs
        mkHomeEvalCheck
        ;
    })
    (import ./home-matrix.nix {
      inherit
        lib
        homes
        homeMatrixOver
        mkHomeMatrix
        ;
    })
    (import ./members.nix {
      inherit
        lib
        loadIdentity
        mkMembers
        ;
    })
    (import ./member-checks.nix {
      inherit
        lib
        pkgs
        toolkit
        mkMembers
        mkMemberChecks
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
