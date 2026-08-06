# nixosModules.greeter — the contract's REFERENCE runtime greeter (ADR-0006, ADR-0008).
#
# This is the "reference & replaceable program" half of the greeter (ADR-0008): the greetd
# integration, the eval-free auth flow, and the privileged runtime-provisioning helper. It is
# opt-in (`custom.greeter.enable`) — a seat host enables it, a headless host simply never does
# (incapacity, not a ban). It is the ONE place the contract ships scripts that reference real
# packages; this does NOT break ADR-0004's package-free invariant, because those packages come
# from the HOST's `pkgs` at module-eval time — the contract FLAKE still inputs only nixpkgs
# `lib`. A host may disable this module and supply its own greeter program (its own UI, greetd
# integration, provisioning policy) as long as it honours the canonical mechanism (ADR-0008):
#   (1) authenticate EVAL-FREE on identity.json before any user Nix runs,
#   (2) build the user's OWN home output through the contract umbrella (the homeBuilder binding,
#       under the tier's restricted-eval posture) and realize the account via `provision`,
#   (3) grant AT MOST the safeSet.
#
# The flow (ADR-0006 "data before code" — authenticate on inert data before running any Nix) is one
# program per step, each in ./greeter/ so this module stays a thin schema + wiring layer:
#   1. prompt (flake URL, username, password)              — replaceable UI    } ./greeter/bind.nix
#   2. fetch SOURCE + input closure (nix flake archive)   — no user Nix yet    } (the orchestrator)
#   3. authenticate EVAL-FREE (jq identity.json: password + Tier-1 sig, ADR-0011) — ./greeter/auth.nix
#   4. classify the tier                                   — host policy (custom.greeter.tier)
#   5/6. build the home under the PINNED restricted-eval posture (ADR-0014) — host BINDING (homeBuilder)
#   7. provision: FULLY realize the account + activate the home — CRUX        — ./greeter/provision.nix
#   8. launch the session — the user's chosen DESKTOP (ADR-0013)             — ./greeter/session.nix
#
# Runtime grant effects are a STANDING greeter-seat baseline, not a per-login rebuild (ADR-0010):
# this module declares the safe set's group memberships + a `greeter-users` marker group, and
# `provision` enrolls the account into them. `provision` is the runtime, shell-side equivalent of
# `realization.nix` (ADR-0012): it fully realizes the account from identity.json + the safe-set
# grant (password, authorizedKeys, GECOS, the CLAMPED safe groups) so a greeter user realizes
# IDENTICALLY to a build-time one — the portable-user north star: same identity, any seat, same
# experience.
{
  lib,
  privilegedGroups,
  grantLib,
  greeterGrants,
  tier1EvalConfig,
  renderNixConfig,
  identityFile,
}:
let
  # The safe set's group memberships — the system-side effect greeterGrants confers (ADR-0010).
  # For the safe set `["gui"]` this is gui's input groups; they form the standing greeter-seat
  # baseline this module declares + `provision` enrolls each account into. Single-sourced through
  # grantLib's grant→groups fold over greeterGrants (issue #28) — the same fold realization.nix uses
  # for a build-time account, so the greeter-seat baseline and a realized account earn groups
  # identically.
  baselineGroups = lib.unique (grantLib.grantedGroups greeterGrants);
  enrolledGroups = baselineGroups ++ [ "greeter-users" ];

  # The Tier-1 restricted-eval posture (ADR-0014), rendered to a NIX_CONFIG body the greeter
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
  cfg = config.custom.greeter;

  # The shipped programs, one per file (the canonical mechanism + the replaceable UI). Each is
  # a writeShellApplication closed over only what it needs; bind orchestrates the rest.
  authScript = import ./greeter/auth.nix { inherit pkgs identityFile; };
  provisionScript = import ./greeter/provision.nix {
    inherit
      pkgs
      lib
      privilegedGroups
      enrolledGroups
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
  };
in
{
  options.custom.greeter = {
    enable = lib.mkEnableOption ''
      the contract's reference runtime greeter (greetd + the eval-free bind→safe-set-grant→provision
      flow, ADR-0006/0008). A seat host enables it; a headless host simply does not (incapacity, not
      a ban). The contract evaluates with this module present but unbound exactly as with the platform
      interface unbound (ADR-0008 litmus test)'';

    tier = lib.mkOption {
      type = lib.types.enum [
        "tier1"
        "tier2"
      ];
      default = "tier1";
      description = ''
        The trust tier this seat binds at (host POLICY, ADR-0006). `tier1` (semi-trusted, own
        identities): the repo must be signed by a host-trusted key, the home is persisted, and
        eval runs under the contract-pinned restricted-eval posture (ADR-0014, `tier1EvalConfig`) to
        guard accidents and stop the repo widening its own eval — built now. `tier2` (untrusted,
        anyone): ephemeral home, hardened eval — designed-for but DEFERRED, so the provisioning
        helper refuses it today.
      '';
    };

    tier1EvalConfig = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.bool lib.types.str);
      readOnly = true;
      default = tier1EvalConfig;
      description = ''
        Read-only introspection of the Tier-1 restricted-eval posture (ADR-0014): the canonical Nix
        settings the greeter hands the `homeBuilder` as NIX_CONFIG when it builds a host-signed home.
        Fixed to the contract's `tier1EvalConfig` — `accept-flake-config = false` (the repo cannot
        widen its own eval, ADR-0011), `restrict-eval`, no IFD, and a sandboxed build. A host may add
        restrictions in its homeBuilder, never remove these.
      '';
    };

    trustedSigners = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Tier-1 allowed signers: SSH public keys whose signature over a user repo marks it
        semi-trusted (ADR-0006, ADR-0011). This is the host's trust BINDING and the SOLE Tier-1
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
        Host BINDING (ADR-0008 "the host supplies only bindings"): a command invoked as
        `homeBuilder <src> <username>` that builds the user's OWN home output through the contract
        umbrella (typically `nix build "<src>#homeConfigurations.<username>.activationPackage"`)
        under the tier's restricted-eval posture and prints the built home-activation package path.
        It is null by default because building a real home needs home-manager, which the contract
        does not depend on (ADR-0004); the host
        supplies it, exactly as it supplies the platform and display bindings. The reference greeter
        ships everything else — greetd wiring, the eval-free auth ordering, the runtime
        provisioning helper, and session selection — package-free at the flake level.
      '';
    };

    desktops = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            command = lib.mkOption {
              type = lib.types.str;
              description = "The self-contained command that launches this desktop's session (its `wayland-sessions`/`xsessions` Exec). The SEAT owns the session type: if the desktop needs `XDG_SESSION_TYPE` or other session env, the command sets it itself — the contract does not know wayland vs x11 (ADR-0021).";
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
        Host BINDING (ADR-0013): the desktops this seat offers, keyed by the free-form name a user
        requests via `contract.requests.gui.desktop`. The contract ships no desktop (ADR-0004); the
        seat enables its DEs and binds each one's session-entry command here, exactly as a display
        manager launches them. A user's requested name that is not offered degrades to `defaultDesktop`.
      '';
    };

    defaultDesktop = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The `desktops` name to launch when the user requests none, or requests one this seat does not offer (ADR-0013).";
    };

    grants = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.bool);
      readOnly = true;
      default = greeterGrants;
      description = ''
        Read-only introspection of the runtime grant a greeter login receives — fixed to
        `greeterGrants` (default-open over the safe set, ADR-0008 condition 3). It cannot be
        widened here; the greeter auto-grants every runtime-eligible feature and nothing more.
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

    # The greeter-seat baseline (ADR-0010): the safe set's group memberships + a `greeter-users`
    # marker group are pre-realized once, declaratively, so `provision` only ENROLLS each runtime
    # account into them — no per-login rebuild. Declared empty so a host's own gui binding (which
    # may set a gid) merges cleanly.
    users.groups = lib.genAttrs enrolledGroups (_: { });

    # The bind/auth/provision/session scripts are on PATH so the helpers (and a host's own greeter
    # UI) can call them; provision is the privileged crux greetd invokes pre-session.
    environment.systemPackages = [
      bindScript
      authScript
      provisionScript
      sessionScript
    ];
  };
}
