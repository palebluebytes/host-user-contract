# Conformance domain: mkContractPackage (ADR-0032, issue #14) and bindContractPackage
# (ADR-0032, issue #16). mkContractPackage is proven by an execution proof (the derivation
# builds and has correct content). bindContractPackage is proven at eval level: the same
# gui-session union and account that bindUserModule produces emerges from reading a pre-built
# contract-requests.json fixture — same `mkUserAccount` + `bridgeRequests` kernel, different
# data source. The fixture is a plain repo path (no derivation, no IFD).
{
  lib,
  pkgs,
  toolkit,
  mkContractPackage,
  bindContractPackage,
  greeterGrants,
}:
let
  inherit (toolkit) eval exampleIdentity;

  # --- mkContractPackage execution proof (issue #14) ---
  # A minimal activationPackage stub: just an `activate` script at the root.
  activationStub = pkgs.runCommand "mkContractPackage-activation-stub" { } ''
    mkdir -p $out
    printf '#!/bin/sh\necho activated\n' > $out/activate
    chmod +x $out/activate
  '';

  # Build a real contractPackage from known inputs. The manifest is constructed at eval time
  # (builtins.toFile, no IFD); the derivation just copies both files.
  contractPackage = mkContractPackage {
    inherit pkgs;
    activationPackage = activationStub;
    requests = {
      gui = {
        session = "x11";
        desktop = "plasma";
      };
    };
    packages = [ pkgs.hello ];
    username = "testuser";
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

        jq -e '.version == 1'              "$manifest"
        jq -e '.username == "testuser"'    "$manifest"
        jq -e '.packages | contains(["hello"])' "$manifest"
        jq -e '.requests.gui.session == "x11"'  "$manifest"
        jq -e '.requests.gui.desktop == "plasma"' "$manifest"

        touch $out
      '';

  # --- bindContractPackage eval proof (issue #16) ---
  # Use a plain repo-path fixture (no derivation build needed, no IFD) so the eval assertions
  # stay pure. The fixture mirrors the example user's request: gui.session = "x11".
  fixturePackage = ./fixtures/example-contract-package;

  boundRuntime = eval [
    (bindContractPackage {
      contractPackage = fixturePackage;
      identity = exampleIdentity;
      grants = greeterGrants;
    })
  ];
  boundNone = eval [
    (bindContractPackage {
      contractPackage = fixturePackage;
      identity = exampleIdentity;
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

    # bindContractPackage: account materializes from identity
    {
      name = "bindContractPackage: the account materializes from identity";
      ok =
        boundRuntime.users.users.example.isNormalUser
        && boundRuntime.users.users.example.description == "Example User";
    }

    # bindContractPackage: granted request bridges to the gui union (parity with bindUserModule)
    {
      name = "bindContractPackage: a granted gui request bridges to the union (x11)";
      ok = boundRuntime.custom.gui.surface.enabled && boundRuntime.custom.gui.surface.x11;
    }

    # bindContractPackage: ungranted request is inert
    {
      name = "bindContractPackage: an ungranted request is inert (no surface)";
      ok = !boundNone.custom.gui.surface.enabled;
    }

    # bindContractPackage: activation script is registered in the system
    {
      name = "bindContractPackage: activation script is registered";
      ok = boundRuntime.system.activationScripts ? "contract-activate-example";
    }

    # bindContractPackage: no package policy profile replacement when allowedPrograms is empty
    {
      name = "bindContractPackage: no profile replacement when allowedPrograms is empty (default)";
      ok =
        let
          scriptText = boundRuntime.system.activationScripts."contract-activate-example".text or "";
        in
        !(lib.hasInfix "nix-profile" scriptText);
    }
  ];

  drvs = {
    "contract-package-content-check" = contentCheck;
  };
}
