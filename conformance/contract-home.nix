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
    memberDir = ../examples/users/users/ada;
    # The SESSION SHAPE this home is built for (ADR-0032) — the only thing a producer tells a home
    # about the world outside it, beyond the platform and the exposure fact.
    mode = "gui";
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

  # An explicit identity must override the memberDir loader, and the fixed home.* rules follow it.
  overridden = mkContractHome {
    homeManagerConfiguration = recordingHMC;
    pkgs = stubPkgs;
    memberDir = ../examples/users/users/ada;
    identity = {
      username = "sol";
    };
    mode = "cli";
    stateVersion = "26.05";
  };
  overriddenInline = inlineOf overridden;

  # --- the member as the builder's input (issue #57) ---
  # A `mkMembers` entry, stood in for by hand so this stays a claim about the BUILDER: its
  # `dir` is ada's real directory while its `identity` is somebody else's. Both must be taken from
  # the member — which is only possible if the builder no longer re-resolves `<dir>/identity.json`
  # for itself. The members resolved it once; a third resolution site is what this removes.
  memberBuilt = mkContractHome {
    homeManagerConfiguration = recordingHMC;
    pkgs = stubPkgs;
    member = {
      name = "ada";
      dir = ../examples/users/users/ada;
      identity = {
        username = "rosa";
      };
    };
    mode = "cli";
    stateVersion = "25.11";
  };
  memberInline = inlineOf memberBuilt;

  # Neither a member nor a memberDir: there is no user directory to compose from, so this is a named
  # error rather than a home assembled from a missing path.
  sourcelessEval = builtins.tryEval (
    lib.elemAt
      (mkContractHome {
        homeManagerConfiguration = recordingHMC;
        pkgs = stubPkgs;
        mode = "cli";
        stateVersion = "25.11";
      }).modules
      2
  );

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
      name = "mkContractHome: an explicit identity overrides the memberDir loader; home.* follow it";
      ok =
        overriddenInline.identity.username == "sol"
        && overriddenInline.home.username == "sol"
        && overriddenInline.home.homeDirectory == "/home/sol"
        && overriddenInline.home.stateVersion == "26.05";
    }

    # --- the member (issue #57) ---
    {
      name = "mkContractHome: a member supplies the memberDir AND the already-resolved identity";
      ok =
        lib.elemAt memberBuilt.modules 2 == ../examples/users/users/ada/home.nix
        && memberInline.identity.username == "rosa"
        && memberInline.home.username == "rosa"
        && memberInline.home.homeDirectory == "/home/rosa";
    }
    {
      name = "mkContractHome: with neither a member nor a memberDir there is no home to compose ⇒ hard error";
      ok = !sourcelessEval.success;
    }

    # --- the specialArgs: hostFacts is contract-owned; the rest is opaque passthrough ---
    {
      # The whole of what a home is told: the MODE it was built for, the platform (read off the
      # caller's own pkgs, never ambient), and the exposure fact. `granted` is deliberately absent —
      # no grant can change a home, so showing one the grant set would be showing it something it
      # must not use (ADR-0032 §7).
      name = "mkContractHome: hostFacts is { mode; platform; exposed } — no grant reaches a home";
      ok =
        recorded.extraSpecialArgs.hostFacts == {
          exposed = false;
          mode = "gui";
          platform = "riscv64-linux";
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

    {
      # NOTHING is appended to the builder's own result. The `contractBakedGrantKey` marker the
      # producer coin used to cross-check is gone with the pairing it protected (ADR-0032): a home
      # is published under the very mode it was built for, so there is no second record to disagree
      # with. The recording stub returns its arguments verbatim, so the result's attribute set IS
      # exactly what the builder composed.
      name = "mkContractHome: the result is the builder's own arguments — no marker rides it";
      ok =
        lib.attrNames recorded == [
          "extraSpecialArgs"
          "modules"
          "pkgs"
        ];
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
