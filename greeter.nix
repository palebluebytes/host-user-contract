# nixosModules.greeter — the contract's REFERENCE runtime greeter, and the NORTH STAR path.
#
# Any seat host running this takes a flake URL, a username and a password, and transparently
# enables that user — with a graphical session by default on any seat that declared it has a
# display. Nothing about the USER is declared in advance on either side: they are a stranger to
# this machine until they type their URL.
#
# This is the "reference & replaceable program" half: the greetd integration, the eval-free auth
# flow, mode selection, and the privileged runtime-provisioning helper. It is opt-in
# (`contract.greeter.enable`) — a seat host enables it, a headless host simply never does (incapacity,
# not a ban). It is the ONE place the contract ships scripts that reference real packages; that does
# NOT break the package-free invariant, because those packages come from the HOST's `pkgs` at
# module-eval time — the contract FLAKE still inputs only nixpkgs `lib`. A host may disable this
# module and supply its own greeter program (its own UI, greetd integration, provisioning policy) as
# long as it honours the canonical mechanism:
#   (1) authenticate EVAL-FREE on identity.json before any user Nix runs,
#   (2) SELECT the session shape from what the user publishes and what this seat runs, build that
#       home output (the homeBuilder binding, under the tier's restricted-eval posture) and realize
#       the account via `provision`,
#   (3) confer AT MOST the safe set — which is empty, so: confer nothing.
#
# The flow ("data before code" — authenticate on inert data before running any Nix) is one
# program per step, each in ./greeter/ so this module stays a thin schema + wiring layer:
#   1. prompt (flake URL, username, password)              — replaceable UI    } ./greeter/bind.nix
#   2. fetch SOURCE + input closure (nix flake archive)   — no user Nix yet    } (the orchestrator)
#   3. authenticate EVAL-FREE (jq identity.json: password + Tier-1 signature) — ./greeter/auth.nix
#   4. classify the tier                                   — host policy (contract.greeter.tier)
#   4b. SELECT THE MODE: read the user's published modes off the flake's binding index and
#       intersect them with what this seat runs — the same selection a declarative bind makes
#   5/6. build the home under the PINNED restricted-eval posture — host BINDING (homeBuilder)
#   7. provision: FULLY realize the account + activate the home — CRUX        — ./greeter/provision.nix
#   8. launch the session — the user's chosen DESKTOP                        — ./greeter/session.nix
#
# Runtime grant effects are a STANDING greeter-seat baseline, not a per-login rebuild: this module
# declares the safe set's group memberships + a `greeter-users` marker group, and `provision`
# enrolls the account into them. `provision` is the runtime, shell-side equivalent of
# `realization.nix`: it fully realizes the account from identity.json + the selected mode's groups
# (password, authorizedKeys, GECOS, the CLAMPED safe groups) so a greeter user realizes
# IDENTICALLY to a build-time one — modulo the `greeter-users` seat marker, which is seat
# infrastructure layered on top, not part of the portable account — the portable-user north star:
# same identity, any seat, same experience.
{
  lib,
  modeRegistry,
  greeterAffordances,
  runsWith,
  tier1EvalConfig,
  renderNixConfig,
  identityFile,
  identityFields,
}:
let
  # The Tier-1 restricted-eval posture, rendered to a NIX_CONFIG body the greeter
  # exports to the host's homeBuilder. Single-sourced from the contract's canonical tier1EvalConfig
  # via the contract's own renderer, so what the greeter applies is exactly what conformance proves.
  tier1NixConfig = renderNixConfig tier1EvalConfig;
in
{
  config,
  pkgs,
  ...
}:
let
  cfg = config.contract.greeter;

  # WHAT THIS SEAT RUNS, and it is a property of the MACHINE rather than of the contract. It used
  # to be `runsFor safeSet` — a constant, identical on every host, which meant a greeter-enabled
  # box with no display still claimed to run a graphical session and would select a graphical home
  # for a walk-up user. Reading the machine's own declaration fixes that at the root.
  runs = runsWith config.contract.modes;

  # The group memberships a seat's sessions need — the standing greeter-seat baseline this module
  # pre-realizes and `provision` enrolls each account into. Derived from the MODES this machine
  # runs, because that is where session groups live: a graphical session needs its input devices
  # by virtue of being graphical. `accountPlan` (which `provision` evaluates) folds the selected
  # mode's groups into the record for each user; `enrolledGroups` re-adds the whole seat's set
  # alongside the `greeter-users` MARKER — the one group beyond the portable account (a build-time
  # user never gets it), which is why the marker lives here on the seat side rather than inside the
  # seat-agnostic accountPlan.
  baselineGroups = lib.unique (lib.concatMap (m: modeRegistry.${m}.groups or [ ]) runs);
  enrolledGroups = baselineGroups ++ [ "greeter-users" ];

  # The shipped programs, one per file (the canonical mechanism + the replaceable UI). Each is
  # a writeShellApplication closed over only what it needs; bind orchestrates the rest.
  authScript = import ./greeter/auth.nix { inherit pkgs identityFile identityFields; };

  # The account-plan evaluator: the tool `provision` execs to compute the
  # account record from the ONE shared `accountPlan`, instead of re-spelling the fold in jq. Built
  # here (it needs `pkgs`, which the pure kit lacks) exactly as auth/provision/session are.
  accountPlanEval = import ./greeter/account-plan-eval.nix { inherit pkgs; };
  # The mode-selection evaluator: the contract's own `selectModeOver`, executed at login so the
  # greeter and a declarative bind cannot come to different answers. Built here (it needs `pkgs`)
  # exactly as the account-plan evaluator is, and for exactly the same reason — a rule with two
  # spellings is a rule with two behaviours.
  modeSelectEval = import ./greeter/mode-select-eval.nix {
    inherit pkgs;
    # The seat's run set, frozen to store JSON. It can no longer be read out of the contract
    # source — it is a fact about THIS machine — so it joins the two files below as a build-time
    # fact the login-time tools read. That also makes it auditable: `cat` this path and you know
    # what the box will offer a stranger.
    inherit runsFile;
  };
  # What a greeter affords (the empty safe set), the seat's run set, and the seat's enrolled
  # groups, all frozen to store JSON the login-time tools read. `provision` passes the grant to the
  # account-plan evaluator and unions the record's groups with `seatGroupsFile` (the baseline ∪ the
  # `greeter-users` marker) before enrolling.
  greeterGrantsFile = pkgs.writeText "greeter-grants.json" (builtins.toJSON greeterAffordances);
  runsFile = pkgs.writeText "greeter-runs.json" (builtins.toJSON runs);
  seatGroupsFile = pkgs.writeText "greeter-seat-groups.json" (builtins.toJSON enrolledGroups);
  provisionScript = import ./greeter/provision.nix {
    inherit
      pkgs
      accountPlanEval
      greeterGrantsFile
      seatGroupsFile
      ;
  };
  sessionScript = import ./greeter/session.nix {
    inherit pkgs lib;
    inherit (cfg) desktops defaultDesktop;
  };
  bindScript = import ./greeter/bind.nix {
    inherit
      pkgs
      lib
      identityFile
      tier1NixConfig
      authScript
      provisionScript
      sessionScript
      ;
    inherit (cfg)
      tier
      trustedSigners
      homeBuilder
      ;
    modeSelectScript = modeSelectEval;
    # The seat's own system, so the mode selection can look this user up in the flake's binding
    # index (`contractUsers.<system>.<user>`). Read off the host's `pkgs`, exactly as a declarative
    # bind reads it — the two paths must agree about which system's index they are reading.
    system = pkgs.stdenv.hostPlatform.system;
  };
in
{
  options.contract.greeter = {
    enable = lib.mkEnableOption ''
      the contract's reference runtime greeter (greetd + the eval-free
      bind→select→build→provision flow). A seat host enables it; a headless host simply does not
      (incapacity, not a ban). The contract evaluates with this module present but unbound'';

    tier = lib.mkOption {
      type = lib.types.enum [
        "tier1"
        "tier2"
      ];
      default = "tier1";
      description = ''
        The trust tier this seat binds at (host POLICY). `tier1` (semi-trusted, own identities):
        the repo must be signed by a host-trusted key, the home is persisted, and eval runs under
        the contract-pinned restricted-eval posture (`tier1EvalConfig`) to guard accidents and stop
        the repo widening its own eval — built now. `tier2` (untrusted, anyone): ephemeral home,
        hardened eval — designed-for but DEFERRED, so the provisioning helper refuses it today.
      '';
    };

    tier1EvalConfig = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.bool lib.types.str);
      readOnly = true;
      default = tier1EvalConfig;
      description = ''
        Read-only introspection of the Tier-1 restricted-eval posture: the canonical Nix settings
        the greeter hands the `homeBuilder` as NIX_CONFIG when it builds a host-signed home. Fixed
        to the contract's `tier1EvalConfig` — `accept-flake-config = false` (the repo cannot widen
        its own eval), `restrict-eval`, no IFD, and a sandboxed build. A host may add restrictions
        in its homeBuilder, never remove these.
      '';
    };

    trustedSigners = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Tier-1 allowed signers: SSH public keys whose signature over a user repo marks it
        semi-trusted. This is the host's trust BINDING and the SOLE Tier-1
        authority — empty means no repo is Tier-1 on this seat, and a repo cannot vouch for its own
        tier. Distinct from the user's `identity.json.trustedKeys`, which are SSH LOGIN keys.
      '';
    };

    homeBuilder = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.oneOf [
          lib.types.str
          lib.types.path
          lib.types.package
        ]
      );
      default = null;
      description = ''
        Host BINDING ("the host supplies only bindings"): a command invoked as
        `homeBuilder <src> <username> <mode>` that builds the user's OWN home output through the
        contract umbrella (typically
        `nix build "<src>#homes.<system>.<username>.<mode>.activationPackage"`) under the tier's
        restricted-eval posture, and prints the built home-activation package path.

        The MODE is chosen by the greeter, not by this binding: the orchestrator reads the user's
        published modes off the flake's binding index and intersects them with what this seat runs,
        so a seat never hardcodes `gui` and a user who publishes only a terminal home gets one
        rather than a `nix build` failure at the login prompt. A greeter binds an ORDINARY home —
        there is no greeter-specific artifact, since a grant can never reach a home — so this is a
        plain `nix build` against the nested `homes` output.

        It is null by default because building a real home needs home-manager, which the contract
        does not depend on; the host supplies it, exactly as it supplies the display bindings. The
        reference greeter ships everything else — greetd wiring, the eval-free auth ordering, mode
        selection, the runtime provisioning helper, and session selection — package-free at the
        flake level.
      '';
    };

    desktops = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            command = lib.mkOption {
              type = lib.types.str;
              description = "The self-contained command that launches this desktop's session (its `wayland-sessions`/`xsessions` Exec). The SEAT owns the session type: if the desktop needs `XDG_SESSION_TYPE` or other session env, the command sets it itself — the contract does not know wayland vs x11.";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          gnome.command = "''${pkgs.gnome-session}/bin/gnome-session";
          plasma.command = "''${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland";
        }
      '';
      description = ''
        Host BINDING: the desktops this seat offers, keyed by the free-form name a user asks for
        via `contract.gui.desktop` in their `user.nix`. The contract ships no desktop; the seat enables its DEs and
        binds each one's session-entry command here, exactly as a display manager launches them. A
        requested name this seat does not offer degrades to `defaultDesktop`.
      '';
    };

    defaultDesktop = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The `desktops` name to launch when the user asks for none, or asks for one this seat does not offer.";
    };

    affordances = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      readOnly = true;
      default = greeterAffordances;
      description = ''
        Read-only introspection of what this seat confers on a walk-up user — the contract's
        `greeterAffordances`, which is the SAFE SET and is currently EMPTY. There is no operator in
        the loop at a greeter, so a stranger receives every runtime-eligible feature and nothing
        more; every feature in the registry carries privileged groups, so that is nothing at all.
        A stranger gets a SESSION, not powers.
      '';
    };

    runs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = runs;
      description = ''
        Read-only introspection of the MODES this seat runs — the floor plus whatever
        `contract.modes` declares, through the same derivation a declarative bind uses, so the two
        paths cannot come to different answers about what this machine can run. The bind
        orchestrator selects a login's mode over this set intersected with what the user publishes.

        This is what makes "gui by default" true for a stranger with a flake URL: a seat with a
        display declares it once, runs the gui mode for everybody, and the mode carries its own
        input groups. Nothing is granted to make that happen — and a seat WITHOUT a display no
        longer claims otherwise.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # greetd runs the bind orchestrator as the seat's login program. The default_session command
    # is mkDefault so a host can substitute regreet/its own UI (the replaceable half) while the
    # binding scripts below stay canonical.
    services.greetd = {
      enable = true;
      settings.default_session.command = lib.mkDefault "${bindScript}/bin/contract-greeter-bind";
    };

    # The greeter-seat baseline: the groups this seat's session shapes need + a `greeter-users`
    # marker group, pre-realized once, declaratively, so `provision` only ENROLLS each runtime
    # account into them — no per-login rebuild. Declared empty so a host's own display binding
    # (which may set a gid) merges cleanly.
    users.groups = lib.genAttrs enrolledGroups (_: { });

    # The bind/auth/provision/session scripts are on PATH so the helpers (and a host's own greeter
    # UI) can call them; provision is the privileged crux greetd invokes pre-session.
    environment.systemPackages = [
      bindScript
      authScript
      provisionScript
      sessionScript
      accountPlanEval
      modeSelectEval
    ];
  };
}
