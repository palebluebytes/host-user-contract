# Conformance domain: mkContractPackage (ADR-0016, issue #14), its home-manager producer
# adapter mkContractPackageForHome (issue #23), and bindContractPackage (ADR-0016, issue #16).
# mkContractPackage is proven by an execution proof (the derivation builds and has correct
# content); mkContractPackageForHome by an eval-level equivalence proof (a synthetic home
# forwards to the SAME content-addressed store path). bindContractPackage is proven at eval
# level: the same gui surface and account that bindUserModule produces emerges from reading a
# pre-built contract-requests.json fixture — same `mkUserAccount` + `bridgeRequests` kernel,
# different data source. The fixture is a plain repo path (no derivation, no IFD).
{
  pkgs,
  toolkit,
  mkContractPackage,
  mkContractPackageForHome,
  bindContractPackage,
  greeterGrants,
}:
let
  inherit (toolkit) eval referenceIdentity;

  # --- mkContractPackage execution proof (issue #14) ---
  # A minimal activationPackage stub: just an `activate` script at the root.
  activationStub = pkgs.runCommand "mkContractPackage-activation-stub" { } ''
    mkdir -p $out
    printf '#!/bin/sh\necho activated\n' > $out/activate
    chmod +x $out/activate
  '';

  # The four primitives, single-sourced so the direct call and the adapter's synthetic home draw
  # from the SAME values — the equivalence proof below then attests the adapter reads the right
  # attribute PATHS, not that two hand-typed literal sets happen to coincide.
  primitives = {
    requests = {
      gui.desktop = "plasma";
    };
    packages = [ pkgs.hello ];
    username = "testuser";
  };

  # Build a real contractPackage from known inputs. The manifest is constructed at eval time
  # (builtins.toFile, no IFD); the derivation just copies both files.
  contractPackage = mkContractPackage {
    inherit pkgs;
    activationPackage = activationStub;
    inherit (primitives) requests packages username;
  };

  # --- mkContractPackageForHome adapter proof (issue #23) ---
  # The home-manager producer adapter only READS the four primitives off an already-evaluated
  # home (no home-manager import — ADR-0004). A synthetic home whose attribute paths mirror a
  # `homeManagerConfiguration` result stands in for a real one: proving the adapter is exactly
  # the disassembly `mkContractPackage` expects needs no home-manager in the loop. It carries the
  # SAME primitives, placed at the home attribute paths the adapter reads.
  syntheticHome = {
    activationPackage = activationStub;
    config = {
      contract.requests = primitives.requests;
      home = {
        inherit (primitives) packages username;
      };
    };
  };

  # The adapter forwards those primitives into `mkContractPackage`. With identical inputs the
  # derivation is content-addressed to the SAME store path as the direct call above — an
  # eval-level equivalence proof that the adapter extracts every attribute correctly and adds
  # nothing of its own (same name, same activate, same manifest).
  contractPackageFromHome = mkContractPackageForHome {
    inherit pkgs;
    home = syntheticHome;
  };

  # Execution proof: build the derivation and verify its content.
  contentCheck =
    pkgs.runCommand "contract-package-content-check" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        echo "--- activate ---"
        test -x ${contractPackage}/activate

        echo "--- contract-requests.json ---"
        manifest=${contractPackage}/contract-requests.json
        jq . "$manifest"

        jq -e '.version == 2'              "$manifest"
        jq -e '.username == "testuser"'    "$manifest"
        jq -e '.packages | contains(["hello"])' "$manifest"
        jq -e '.requests.gui.desktop == "plasma"' "$manifest"

        touch $out
      '';

  # --- bindContractPackage eval proof (issue #16) ---
  # Use a plain repo-path fixture (no derivation build needed, no IFD) so the eval assertions
  # stay pure. The fixture mirrors the reference user ada's request: gui.desktop = "plasma".
  fixturePackage = ./fixtures/reference-contract-package;

  boundRuntime = eval [
    (bindContractPackage {
      contractPackage = fixturePackage;
      identity = referenceIdentity;
      grants = greeterGrants;
    })
  ];
  boundNone = eval [
    (bindContractPackage {
      contractPackage = fixturePackage;
      identity = referenceIdentity;
      grants = { };
    })
  ];
in
{
  assertions = [
    # mkContractPackage (execution proof lives in drvs; the eval assertion checks the drv exists)
    {
      name = "mkContractPackage: produces a derivation (content verified by execution proof)";
      ok = contractPackage ? outPath;
    }

    # mkContractPackageForHome: the home adapter is exactly the disassembly mkContractPackage
    # expects — same content-addressed store path as the direct call from equal primitives.
    {
      name = "mkContractPackageForHome: reads home primitives into an identical contractPackage";
      ok = contractPackageFromHome.outPath == contractPackage.outPath;
    }

    # bindContractPackage: account materializes from identity
    {
      name = "bindContractPackage: the account materializes from identity";
      ok =
        boundRuntime.users.users.ada.isNormalUser
        && boundRuntime.users.users.ada.description == "Ada Reference";
    }

    # bindContractPackage: granted request enables the gui surface (parity with bindUserModule)
    {
      name = "bindContractPackage: a granted gui request enables the display surface";
      ok = boundRuntime.custom.gui.surface.enabled;
    }

    # bindContractPackage: ungranted request is inert
    {
      name = "bindContractPackage: an ungranted request is inert (no surface)";
      ok = !boundNone.custom.gui.surface.enabled;
    }

    # bindContractPackage: systemd activation service is registered
    {
      name = "bindContractPackage: activation service is registered in systemd";
      ok = boundRuntime.systemd.services ? "contract-activate-ada";
    }

    # bindContractPackage: no package policy profile replacement when allowedPrograms is empty
    {
      name = "bindContractPackage: no profile replacement when allowedPrograms is empty (default)";
      ok =
        let
          svcConfig = boundRuntime.systemd.services."contract-activate-ada".serviceConfig or { };
        in
        !(svcConfig ? ExecStartPost);
    }
  ];

  drvs = {
    "contract-package-content-check" = contentCheck;
  };
}
