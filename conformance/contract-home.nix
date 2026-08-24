# Conformance domain: the producer HOME builder — `mkContractHome` and the home baseline module it
# composes by default. All package-free: `homeManagerConfiguration` is a RECORDING STUB (a function
# returning its own arguments), so every claim is over the arguments the contract composes — the
# module list, the identity/home.* inline module, the hostFacts specialArg — with no home-manager
# anywhere. The baseline's mkDefault posture is proven by a merged `evalModules` over stub
# declarations of the two home-manager option paths it pins.
#
# The claim this domain exists for is the per-mode one: the home a builder composes is the module
# THAT MODE's declaration points at. The reference fleet's TWO-MODULE user is the atom for it —
# two modes naming two different files — and its ONE-MODULE user is the control, naming one file
# twice. Both are borrowed by role through the toolkit's reference seam (./toolkit.nix); this
# domain names no path into `examples/` and nobody in it.
{
  lib,
  toolkit,
  homeBaselineModule,
  mkContractHome,
}:
let
  inherit (toolkit) evalDeclaration referenceHomeModules;
  inherit (toolkit.referenceUsers)
    portable
    cliOnly
    twoModule
    oneModule
    ;

  # The recording stub: whatever the builder composes is returned verbatim for inspection.
  recordingHMC = args: args;

  # A pkgs stand-in carrying ONLY what mkContractHome reads (the platform), on a system that is
  # deliberately NOT the suite's own — proving `platform` is read off the caller's pkgs, never
  # ambient.
  stubPkgs = {
    stdenv.hostPlatform.system = "riscv64-linux";
  };

  # One appended module, structurally comparable, standing in for everything the seam carries
  # (confinement probes, markers, repo glue).
  probe = {
    home.file.".probe".text = "probe";
  };

  build =
    args:
    mkContractHome (
      {
        homeManagerConfiguration = recordingHMC;
        pkgs = stubPkgs;
        stateVersion = "25.11";
      }
      // args
    );

  recorded = build {
    memberDir = portable.dir;
    # The SESSION SHAPE this home is built for — the only thing a producer tells a home about the
    # world outside it, beyond the platform and the exposure fact.
    mode = "gui";
    extraModules = [ probe ];
    # The clobber attempt: hostFacts is contract-owned and must win; everything else (an `inputs`
    # passthrough, say) passes through opaquely.
    extraSpecialArgs = {
      hostFacts = "clobber-attempt";
      inputs = "opaque-inputs";
    };
  };

  # The composition, slot by slot. The order assertion below pins every one of them, so a reorder
  # in mkContractHome fails there loudly rather than silently shifting what these read.
  umbrellaOf = r: (lib.elemAt r.modules 0) { };
  baselineOf = r: (lib.elemAt r.modules 1) { };
  # The desktop dotfile module is a FUNCTION of the mode's `desktop` parameter, so applying it is
  # the whole of what it does: the gui build materialises the file, and a build for a mode with no
  # desktop to choose materialises nothing at all.
  desktopOf = r: (lib.elemAt r.modules 2) { };
  configurationOf = r: lib.elemAt r.modules 3;
  # The MODULES a mode's `configuration` actually names. The deferredModule value itself always
  # differs across two modes — its `_file` records the option path it was defined under, so
  # `contract.gui.configuration` and `contract.cli.configuration` are never equal even when they
  # name one file. So the comparison reaches through to what was NAMED, which is the fact the
  # claims below are actually about.
  namedModules = r: lib.concatMap (m: m.imports or [ ]) (configurationOf r).imports;
  inlineOf = r: lib.elemAt r.modules 4;
  inlineModule = inlineOf recorded;

  # --- the per-mode configuration, and its control ---
  # The two-module user's modes name two DIFFERENT modules, so the composed slot differs across
  # them. The one-module user's two modes name ONE module, so it does not. Without the control,
  # "the two differ" could hold for a reason that has nothing to do with the declaration.
  twoModuleHome =
    mode:
    build {
      memberDir = twoModule.dir;
      inherit mode;
    };
  oneModuleHome =
    mode:
    build {
      memberDir = oneModule.dir;
      inherit mode;
    };

  # An explicit identity must override the memberDir loader, and the fixed home.* rules follow it.
  overridden = build {
    memberDir = portable.dir;
    identity = {
      username = "sol";
    };
    mode = "cli";
    stateVersion = "26.05";
  };
  overriddenInline = inlineOf overridden;

  # --- the member as the builder's input ---
  # A `mkMembers` entry, stood in for by hand so this stays a claim about the BUILDER: its `dir` is
  # the portable user's real directory while its `identity` and its `declaration` are somebody
  # else's. All three must be taken from the member — which is only possible if the builder no
  # longer re-resolves `<dir>/identity.json` or `<dir>/user.nix` for itself.
  memberBuilt = build {
    member = {
      inherit (portable) name dir;
      identity = {
        username = "rosa";
      };
      declaration = evalDeclaration [
        {
          contract.cli = {
            enable = true;
            configuration = ./fixtures/members/pip/home.nix;
          };
        }
      ];
    };
    mode = "cli";
  };
  memberInline = inlineOf memberBuilt;

  # Neither a member nor a memberDir: there is no user directory to compose from, so this is a
  # named error rather than a home assembled from a missing path.
  sourcelessEval = builtins.tryEval (lib.elemAt (build { mode = "cli"; }).modules 3);

  # A mode the user does not run in has no `configuration` to build from, so building it would
  # publish an empty home under a session shape no host could ever select.
  unrunEval = builtins.tryEval (
    lib.elemAt
      (build {
        memberDir = cliOnly.dir;
        mode = "gui";
      }).modules
      3
  );

  # --- the home baseline's mkDefault posture, in a merged eval ---
  # Stub declarations of the two home-manager option paths the baseline pins (this suite evaluates
  # with no home-manager), with CONTRARY upstream defaults so the pin is observable: a mkDefault
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
      name = "mkContractHome: composes umbrella → baseline → desktop → the mode's configuration → inline, then extraModules";
      ok =
        lib.length recorded.modules == 6
        && umbrellaOf recorded ? options
        && (umbrellaOf recorded).options.contract ? identity
        && baselineOf recorded == homeBaselineModule { }
        && configurationOf recorded ? imports
        && lib.last recorded.modules == probe;
    }
    {
      name = "mkContractHome: the inline module carries the loaded identity + the fixed home.* rules";
      ok =
        inlineModule.contract.identity.username == portable.identity.username
        && inlineModule.home.username == portable.identity.username
        && inlineModule.home.homeDirectory == "/home/${portable.identity.username}"
        && inlineModule.home.stateVersion == "25.11";
    }

    # --- THE PER-MODE CLAIM: the home is the module THIS mode's declaration points at ---
    {
      # The two-module user's `user.nix` names one module for `gui` and another for `cli`, so the
      # module the builder composes differs across the two builds. This is what no bind-time grant
      # could ever do: content cannot be injected into a sealed derivation, which is the whole
      # reason a mode is a mode and not a grant.
      name = "mkContractHome: two modes naming two modules compose two DIFFERENT configurations";
      ok =
        namedModules (twoModuleHome "gui") == [ referenceHomeModules.twoModule.gui ]
        && namedModules (twoModuleHome "cli") == [ referenceHomeModules.twoModule.cli ];
    }
    {
      # The control: the one-module user's two modes name ONE module, and compose the same one.
      # Without this, "the two differ" could hold for a reason unrelated to the declaration.
      name = "mkContractHome: two modes naming ONE module compose the SAME configuration (the control)";
      ok =
        namedModules (oneModuleHome "gui") == namedModules (oneModuleHome "cli")
        && namedModules (oneModuleHome "gui") == [ referenceHomeModules.oneModule ];
    }
    {
      # The desktop dotfile carries the gui mode's own `desktop` parameter into the home, where a
      # greeter's launcher reads it before evaluating any of the home's Nix. The portable user asks
      # for plasma; the two-module user asks for sway; and a cli home — a terminal has no desktop
      # to choose — gets nothing, so the mechanism costs a non-graphical home exactly zero.
      name = "mkContractHome: the gui home carries its own desktop choice; the cli home carries none";
      ok =
        (desktopOf recorded).home.file.".contract-desktop".text == "plasma"
        && (desktopOf (twoModuleHome "gui")).home.file.".contract-desktop".text == "sway"
        && desktopOf (twoModuleHome "cli") == { };
    }
    {
      name = "mkContractHome: building a mode the user does not run in is a hard error";
      ok = !unrunEval.success;
    }

    # --- who the home is for ---
    {
      name = "mkContractHome: an explicit identity overrides the memberDir loader; home.* follow it";
      ok =
        overriddenInline.contract.identity.username == "sol"
        && overriddenInline.home.username == "sol"
        && overriddenInline.home.homeDirectory == "/home/sol"
        && overriddenInline.home.stateVersion == "26.05";
    }
    {
      name = "mkContractHome: a member supplies the identity AND the declaration, with no second resolution";
      ok =
        memberInline.contract.identity.username == "rosa"
        && memberInline.home.username == "rosa"
        && memberInline.home.homeDirectory == "/home/rosa"
        # The portable user's own declaration names no configuration at all, so a builder that had
        # re-read `<dir>/user.nix` would compose nothing here rather than the member's own module.
        && namedModules memberBuilt == [ ./fixtures/members/pip/home.nix ]
        && namedModules overridden != namedModules memberBuilt;
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
      # must not use.
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
      # NOTHING is appended to the builder's own result: a home is published under the very mode it
      # was built for, so there is no second record for the producer to cross-check against. The
      # recording stub returns its arguments verbatim, so the result's attribute set IS exactly
      # what the builder composed.
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
