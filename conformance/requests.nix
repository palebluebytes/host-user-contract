# Conformance domain: the user's home-side VOICE — `contract.wants` (WHICH features this user asks
# for, ADR-0028), `contract.supports` (WHICH MODES its home can run in, ADR-0032) and
# `contract.requests` (their PARAMETERS, ADR-0002/0007) — plus the desktop-choice home helper
# (ADR-0013) that surfaces a request to ~/.contract-desktop. All home-side, proven with bare
# evalModules — no home-manager (ADR-0004).
{
  lib,
  toolkit,
  homeModule,
  homeGreeterDesktopModule,
  modes,
  safeSet,
}:
let
  inherit (toolkit) evalHome;

  guiRequest = evalHome [ { contract.requests.gui.desktop = "plasma"; } ];
  # An unknown FEATURE key must now FAIL (ADR-0028 removed the freeformType): a request key the
  # contract does not know is a typo in the user's own repo, not forward-compat.
  unknownRequest = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.requests.bogusFeature.whatever = 42; } ]).contract.requests
      true
  );
  # A misspelled PARAM inside a known feature (gui.desktp) must fail too — the freeform accepted it
  # at any depth, silently yielding the seat default (a wrong desktop with no error).
  misspelledParam = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.requests.gui.desktp = "plasma"; } ]).contract.requests true
  );
  # A malformed KNOWN request must fail to evaluate (the typo-net, ADR-0002). gui.desktop is
  # free-form but still typed `str`, so a wrong-typed value (an int, not a str) errors.
  malformedRequest = builtins.tryEval (
    (evalHome [ { contract.requests.gui.desktop = 42; } ]).contract.requests.gui.desktop
  );

  # --- contract.wants: the user's feature selection, typed, in the home (ADR-0028) ---
  # The enabled feature names of a want/grant set — the same one-bool-per-feature fold the algebra uses
  # (grantLib.grantedNames), spelled here so the domain asserts against the SHAPE it claims.
  wantedNames = w: lib.attrNames (lib.filterAttrs (_: v: v) w);
  defaultWants = (evalHome [ ]).contract.wants;
  privilegedWant = evalHome [ { contract.wants.sudo = true; } ];
  optedOut = evalHome [ { contract.wants.gui = false; } ];
  # No freeform here either: a want for a feature this contract has no registry entry for errors.
  unknownWant = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.wants.bogusFeature = true; } ]).contract.wants true
  );
  # The shape is ONE BOOL PER FEATURE (`{ <feature> = bool; }`, ADR-0032 §3), so the `.enable`
  # suffix it used to carry is now a type error rather than a silently-accepted second shape — the
  # dialect a home written against the old vocabulary speaks.
  dotEnableWant = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.wants.gui.enable = true; } ]).contract.wants true
  );

  # --- contract.supports: which MODES this home can run in (ADR-0032) ---
  supportedNames = sup: lib.attrNames (lib.filterAttrs (_: v: v) sup);
  defaultSupports = (evalHome [ ]).contract.supports;
  guiOnly = evalHome [ { contract.supports.gui = true; } ];
  bothModes = evalHome [
    {
      contract.supports.cli = true;
      contract.supports.gui = true;
    }
  ];
  # Typed off the mode registry and nothing else: a typo'd mode is an eval error in the user's own
  # repo, never a user nothing can bind that a host operator discovers (ADR-0032, rejected
  # free-form mode names).
  unknownMode = builtins.tryEval (
    builtins.deepSeq (evalHome [ { contract.supports.desktop = true; } ]).contract.supports true
  );

  # --- the MODE, derived into the home's own switches (ADR-0032 §7) ---
  # `hostFacts.mode` is the single source, and the umbrella turns it into exactly one true
  # `custom.home.profiles.<mode>.enable`. Evaluated with the specialArg present, which `evalHome`
  # deliberately does not supply — the umbrella must stay evaluable with NO facts at all, and the
  # all-false claim below is that case.
  evalHomeIn =
    mode:
    (lib.evalModules {
      modules = [ homeModule ];
      specialArgs.hostFacts = {
        inherit mode;
        exposed = false;
        platform = "x86_64-linux";
      };
    }).config;
  enabledProfiles = c: lib.attrNames (lib.filterAttrs (_: p: p.enable) c.custom.home.profiles);
  # A home writing its own profile is a CONFLICT, not an override: the mode is a fact handed to the
  # home, not a choice the home makes, so `home-profiles.nix`'s earlier rule is reversed.
  homeWritesItsOwnMode = builtins.tryEval (
    builtins.deepSeq
      (lib.evalModules {
        modules = [
          homeModule
          { custom.home.profiles.gui.enable = true; }
        ];
        specialArgs.hostFacts = {
          mode = "cli";
          exposed = false;
          platform = "x86_64-linux";
        };
      }).config.custom.home.profiles
      true
  );

  # The desktop helper sets `home.file`, a home-manager option the tracer-pure umbrella does not
  # declare, so — exactly as bind.nix's hmStub stands in for `home-manager.users` — a tiny stub
  # declares `home.file` so the helper's logic is provable with no home-manager.
  homeFileStub =
    { lib, ... }:
    {
      options.home.file = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule { options.text = lib.mkOption { type = lib.types.str; }; }
        );
      };
    };
  surfaceDesktop =
    mods:
    (lib.evalModules {
      modules = [
        homeModule
        homeFileStub
        homeGreeterDesktopModule
      ]
      ++ mods;
    }).config;
  desktopChosen = surfaceDesktop [ { contract.requests.gui.desktop = "plasma"; } ];
  desktopUnset = surfaceDesktop [ ];
in
{
  assertions = [
    {
      name = "requests: a known request (gui.desktop) is readable on the home eval";
      ok = guiRequest.contract.requests.gui.desktop == "plasma";
    }
    {
      name = "requests: an unknown feature key is an eval error (no freeform — ADR-0028)";
      ok = !unknownRequest.success;
    }
    {
      name = "requests: a misspelled param in a known feature (gui.desktp) is an eval error";
      ok = !misspelledParam.success;
    }
    {
      name = "requests: a malformed known request (wrong-typed gui.desktop) errors";
      ok = !malformedRequest.success;
    }

    # --- contract.wants (ADR-0028): the user's feature selection lives in the home ---
    {
      # Non-privileged features are wanted by default; privileged ones must be asked for. The
      # default IS the safe set — not a hardcoded gui — so a future non-privileged feature
      # inherits the posture with no new special case.
      name = "wants: the default is exactly the safe set";
      ok = wantedNames defaultWants == safeSet;
    }
    {
      name = "wants: the shape mirrors grantedOptions (<feature> = bool); the old `.enable` errors";
      ok = lib.isBool defaultWants.gui && lib.isBool defaultWants.sudo && !dotEnableWant.success;
    }
    {
      # Asking for a privileged feature must not discard the safe-set default (the default is
      # per-feature, not a whole-submodule default a single definition would replace).
      name = "wants: asking for a privileged feature keeps the safe-set default (gui still wanted)";
      ok = privilegedWant.contract.wants.sudo && privilegedWant.contract.wants.gui;
    }
    {
      name = "wants: a user wanting no desktop opts out explicitly (gui = false)";
      ok = wantedNames optedOut.contract.wants == [ ];
    }
    {
      name = "wants: an unknown feature key is an eval error (no freeform)";
      ok = !unknownWant.success;
    }

    # --- contract.supports (ADR-0032): which modes this home can run in ---
    {
      # NO DEFAULT SUPPLIES THE RULE. Every mode defaults to false — the module system needs a
      # value to merge — so a home that says nothing supports NOTHING, and the bake refuses it by
      # name rather than publishing an empty set (see turnkey-bind's "supports no mode"). A default
      # of "every mode" would set a user's essential nature by inheritance.
      name = "supports: nothing is supported by default — no default satisfies the at-least-one rule";
      ok = supportedNames defaultSupports == [ ];
    }
    {
      # …and the option is declared for EVERY mode the registry names, so a contract that gains a
      # mode gains the option with no edit to the umbrella.
      name = "supports: one option per registry mode, all bools";
      ok =
        lib.attrNames defaultSupports == lib.attrNames modes
        && lib.all (m: lib.isBool defaultSupports.${m}) (lib.attrNames defaultSupports);
    }
    {
      # A gui-only user is expressible: it says gui and nothing else, and a headless host then
      # cannot bind it — a REFUSAL, not a silently lesser home (ADR-0032's narrowing of ADR-0002).
      name = "supports: a user may support one mode alone (gui-only is expressible)";
      ok = supportedNames guiOnly.contract.supports == [ "gui" ];
    }
    {
      name = "supports: a user may support several modes";
      ok =
        supportedNames bothModes.contract.supports == [
          "cli"
          "gui"
        ];
    }
    {
      name = "supports: a mode name the registry does not declare is an eval error (no freeform)";
      ok = !unknownMode.success;
    }

    # --- the mode, derived into the home's switches (ADR-0032 §7) ---
    {
      # EXACTLY ONE TRUE, whichever mode the home was built for. The home writes no wire: the
      # translation line every grant-sensitive home used to carry
      # (`profiles.gui.enable = hostFacts.granted.gui.enable or false`) has nothing left to
      # translate, because no grant reaches a home.
      name = "profiles: hostFacts.mode derives exactly one true profile";
      ok =
        enabledProfiles (evalHomeIn "gui") == [ "gui" ] && enabledProfiles (evalHomeIn "cli") == [ "cli" ];
    }
    {
      # …and with NO facts at all — a bare tracer eval — every profile is false, which is the right
      # answer for a home nothing is running. This is what keeps the umbrella evaluable by bare
      # `evalModules` with no specialArgs (ADR-0004/0008).
      name = "profiles: a home evaluated with no hostFacts has no mode, so no profile is enabled";
      ok = enabledProfiles (evalHome [ ]) == [ ];
    }
    {
      # The reversal, made observable: a home writing its own profile CONFLICTS with the contract's
      # definition rather than overriding it. The mode is an answer, not a claim.
      name = "profiles: a home writing its own mode conflicts — the contract owns the switch";
      ok = !homeWritesItsOwnMode.success;
    }

    {
      # ADR-0013 helper: a requested desktop is auto-surfaced to ~/.contract-desktop verbatim, so the
      # greeter's launcher (which runs before the home Nix) reads the user's choice with no manual step.
      name = "desktop helper: contract.requests.gui.desktop materialises ~/.contract-desktop";
      ok = desktopChosen.home.file.".contract-desktop".text == "plasma";
    }
    {
      # No desktop requested ⇒ no dotfile, so the greeter degrades to the seat default (ADR-0013).
      name = "desktop helper: no desktop request leaves ~/.contract-desktop absent (seat default)";
      ok = !(desktopUnset.home.file ? ".contract-desktop");
    }
  ];
}
