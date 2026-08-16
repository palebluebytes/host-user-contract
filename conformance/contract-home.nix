# Conformance domain: the producer HOME builder (issue #40/#42) — `mkContractHome` and the home
# baseline module it includes by default. All package-free (ADR-0004/0022): `homeManagerConfiguration`
# is a RECORDING STUB (a function returning its own arguments), so every claim is over the arguments
# the contract composes — the module list, the identity/home.* inline module, the hostFacts
# specialArg — with no home-manager anywhere. The baseline's mkDefault posture is proven by a merged
# `evalModules` over stub declarations of the two home-manager option paths it pins.
{
  lib,
  homeGreeterDesktopModule,
  homeBaselineModule,
  mkContractHome,
}:
let
  # The recording stub: whatever the builder composes is returned verbatim for inspection.
  recordingHMC = args: args;

  # A pkgs stand-in carrying ONLY what mkContractHome reads (the platform), on a system that is
  # deliberately NOT the suite's own — proving `platform` is read off the caller's pkgs, never
  # ambient.
  stubPkgs = {
    stdenv.hostPlatform.system = "riscv64-linux";
  };

  # One appended module, structurally comparable, standing in for everything the seam carries
  # (confinement probes, greeterDesktop, markers, repo glue).
  probe = {
    home.file.".probe".text = "probe";
  };

  recorded = mkContractHome {
    homeManagerConfiguration = recordingHMC;
    pkgs = stubPkgs;
    userDir = ../examples/users/users/ada;
    # sudo is a bind-riding grant (not a variant axis): the narrowing must drop it before a home
    # can ever see it (ADR-0028).
    granted = {
      gui.enable = true;
      sudo.enable = true;
    };
    stateVersion = "25.11";
    extraModules = [ probe ];
    # The clobber attempt: hostFacts is contract-owned and must win; everything else (the
    # ADR-0020 `inputs` convention) passes through opaquely.
    extraSpecialArgs = {
      hostFacts = "clobber-attempt";
      inputs = "opaque-inputs";
    };
  };

  # The one owner of "where the inline identity/home.* module sits" (slot 3, after umbrella /
  # baseline / home.nix) — the composition-order assertion below pins the other slots, so a
  # reorder in mkContractHome fails there loudly rather than silently shifting what this reads.
  inlineOf = r: lib.elemAt r.modules 3;
  inlineModule = inlineOf recorded;

  # Nix functions are incomparable (`==` on two lambdas is always false), so module identity is
  # asserted by CONTENT: each composed module function is applied and its body inspected. The
  # umbrella is recognised by the options only it declares; the baseline's applied body is plain
  # data (mkDefault wrappers), so it compares structurally equal to the exposed module's own.
  composedUmbrella = (lib.elemAt recorded.modules 0) { };
  slotOneIsBaseline = (lib.elemAt recorded.modules 1) { } == homeBaselineModule { };

  # The greeterDesktop recogniser: does this function module materialise the greeter's desktop
  # dotfile when a desktop is requested? Applied to the REAL greeterDesktop module as the positive
  # control (a probe that recognises nothing would pass vacuously), then over the composed list.
  desktopProbeArg = {
    config.contract.requests.gui.desktop = "plasma";
  };
  surfacesDesktopChoice =
    m:
    lib.isFunction m
    && lib.hasAttrByPath [
      "content"
      "home"
      "file"
      ".contract-desktop"
    ] (m desktopProbeArg);

  # An explicit identity must override the userDir loader, and the fixed home.* rules follow it.
  overridden = mkContractHome {
    homeManagerConfiguration = recordingHMC;
    pkgs = stubPkgs;
    userDir = ../examples/users/users/ada;
    identity = {
      username = "sol";
    };
    stateVersion = "26.05";
  };
  overriddenInline = inlineOf overridden;

  # --- the home baseline's mkDefault posture, in a merged eval ---
  # Stub declarations of the two home-manager option paths the baseline pins (we evaluate with no
  # home-manager, ADR-0004), with CONTRARY upstream defaults so the pin is observable: a mkDefault
  # definition (prio 1000) must beat an option default (prio 1500).
  stubHomeManagerOptions = {
    options.programs.home-manager.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    options.systemd.user.startServices = lib.mkOption {
      type = lib.types.either lib.types.bool (
        lib.types.enum [
          "suggest"
          "legacy"
          "sd-switch"
        ]
      );
      default = true;
    };
  };
  baselineAlone = lib.evalModules {
    modules = [
      stubHomeManagerOptions
      homeBaselineModule
    ];
  };
  # A user module's PLAIN definition (prio 100) must win per-option — the baseline has no opt-out
  # knob because mkDefault makes every line individually overridable.
  baselineOverridden = lib.evalModules {
    modules = [
      stubHomeManagerOptions
      homeBaselineModule
      {
        programs.home-manager.enable = false;
        systemd.user.startServices = "legacy";
      }
    ];
  };
in
{
  assertions = [
    # --- composition: the module list mkContractHome hands the injected builder ---
    {
      name = "mkContractHome: composes umbrella → baseline → home.nix → inline, then extraModules";
      ok =
        lib.length recorded.modules == 5
        && composedUmbrella.options.contract ? wants
        && composedUmbrella.options.contract ? requests
        && slotOneIsBaseline
        && lib.elemAt recorded.modules 2 == ../examples/users/users/ada/home.nix
        && lib.last recorded.modules == probe;
    }
    {
      name = "mkContractHome: the inline module carries the loaded identity + the fixed home.* rules";
      ok =
        inlineModule.identity.username == "ada"
        && inlineModule.home.username == "ada"
        && inlineModule.home.homeDirectory == "/home/ada"
        && inlineModule.home.stateVersion == "25.11";
    }
    {
      name = "mkContractHome: baseline IS composed by default; greeterDesktop is NOT (opt-in via extraModules)";
      # The baseline is position 1 by content (its mkDefault wrappers are plain data). The
      # greeterDesktop's absence is a negative-space probe with its positive control: the
      # recogniser MUST fire on the real greeterDesktop module, and must fire on nothing composed.
      ok =
        slotOneIsBaseline
        && surfacesDesktopChoice homeGreeterDesktopModule
        && !(lib.any surfacesDesktopChoice recorded.modules);
    }
    {
      name = "mkContractHome: an explicit identity overrides the userDir loader; home.* follow it";
      ok =
        overriddenInline.identity.username == "sol"
        && overriddenInline.home.username == "sol"
        && overriddenInline.home.homeDirectory == "/home/sol"
        && overriddenInline.home.stateVersion == "26.05";
    }

    # --- the specialArgs: hostFacts is contract-owned; the rest is opaque passthrough ---
    {
      name = "mkContractHome: hostFacts is narrowed (bind-riding sudo dropped), platform read off pkgs";
      ok =
        recorded.extraSpecialArgs.hostFacts == {
          exposed = false;
          platform = "riscv64-linux";
          granted = {
            gui = {
              enable = true;
            };
          };
        };
    }
    {
      name = "mkContractHome: extraSpecialArgs cannot clobber hostFacts, but passes through opaquely";
      ok =
        recorded.extraSpecialArgs.hostFacts != "clobber-attempt"
        && recorded.extraSpecialArgs.inputs == "opaque-inputs";
    }
    {
      name = "mkContractHome: pkgs is forwarded verbatim to the injected homeManagerConfiguration";
      ok = recorded.pkgs == stubPkgs;
    }

    # --- the bake key travels with the home (issue #56) ---
    # The built home carries the grant-key it was baked under, so the producer coin can verify the
    # pairing instead of trusting the grant handed alongside. Recorded AS PASSED (sorted enabled
    # names) — deliberately NOT the narrowed hostFacts set, which drops the bind-riding sudo above:
    # the rule a producer holds is "pass the bake the same grant attrset you passed here", and the
    # narrowing is the contract's own downstream step.
    {
      name = "mkContractHome: the built home carries the grant-key it was baked under";
      ok =
        recorded.contractBakedGrantKey == [
          "gui"
          "sudo"
        ];
    }
    {
      name = "mkContractHome: a grant-less bake carries the empty key (not a missing marker)";
      ok = overridden.contractBakedGrantKey == [ ];
    }
    {
      # The marker rides the RESULT and adds exactly one attribute: it must not reach the home's
      # own eval, where it would be a second, spoofable spelling of `hostFacts.granted` — and where
      # an undeclared option would throw. The recording stub returns its arguments verbatim, so the
      # result's attribute set IS the builder's arguments plus whatever mkContractHome appended.
      name = "mkContractHome: the bake key is one added result attribute; the home never sees it";
      ok =
        lib.attrNames recorded == [
          "contractBakedGrantKey"
          "extraSpecialArgs"
          "modules"
          "pkgs"
        ]
        && !(recorded.extraSpecialArgs ? contractBakedGrantKey)
        && !(lib.any (m: lib.isAttrs m && m ? contractBakedGrantKey) recorded.modules);
    }

    # --- the home baseline: hygiene is a PINNED POSTURE, per-option overridable ---
    {
      name = "home baseline: pins hold over upstream option defaults (mkDefault 1000 beats default 1500)";
      ok =
        baselineAlone.config.programs.home-manager.enable
        && baselineAlone.config.systemd.user.startServices == "sd-switch";
    }
    {
      name = "home baseline: a user module's plain definition wins per-option (no opt-out knob)";
      ok =
        !baselineOverridden.config.programs.home-manager.enable
        && baselineOverridden.config.systemd.user.startServices == "legacy";
    }
    {
      name = "home baseline: every definition is mkDefault priority (highestPrio 1000)";
      ok =
        baselineAlone.options.programs.home-manager.enable.highestPrio == 1000
        && baselineAlone.options.systemd.user.startServices.highestPrio == 1000;
    }
  ];
}
