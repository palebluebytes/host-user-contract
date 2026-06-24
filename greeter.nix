# nixosModules.greeter — the contract's REFERENCE runtime greeter (ADR-0022, ADR-0024).
#
# This is the "reference & replaceable program" half of the greeter (ADR-0024): the greetd
# integration, the eval-free auth flow, and the privileged runtime-provisioning helper. It is
# opt-in (`custom.greeter.enable`) — a seat host enables it, a headless host simply never does
# (incapacity, not a ban). It is the ONE place the contract ships scripts that reference real
# packages; this does NOT break ADR-0020's package-free invariant, because those packages come
# from the HOST's `pkgs` at module-eval time — the contract FLAKE still inputs only nixpkgs
# `lib`. A host may disable this module and supply its own greeter program (its own UI, greetd
# integration, provisioning policy) as long as it honours the canonical mechanism (ADR-0024):
#   (1) authenticate EVAL-FREE on identity.json before any user Nix runs,
#   (2) bind via the contract (bindUserModule { grants = greeterGrants; }),
#   (3) grant AT MOST the safeSet.
#
# The flow (ADR-0022 "data before code" — authenticate on inert data before running any Nix) is one
# program per step, each in ./greeter/ so this module stays a thin schema + wiring layer:
#   1. prompt (flake URL, username, password)              — replaceable UI    } ./greeter/bind.nix
#   2. fetch SOURCE + input closure (nix flake archive)   — no user Nix yet    } (the orchestrator)
#   3. authenticate EVAL-FREE (jq identity.json: password + Tier-1 sig, ADR-0027) — ./greeter/auth.nix
#   4. classify the tier                                   — host policy (custom.greeter.tier)
#   5/6. build the home under the PINNED restricted-eval posture (ADR-0030) — host BINDING (homeBuilder)
#   7. provision: FULLY realize the account + activate the home — CRUX        — ./greeter/provision.nix
#   8. launch the session — the user's chosen DESKTOP (ADR-0029)             — ./greeter/session.nix
#
# Runtime grant effects are a STANDING greeter-seat baseline, not a per-login rebuild (ADR-0026):
# this module declares the safe set's group memberships + a `greeter-users` marker group, and
# `provision` enrolls the account into them. `provision` is the runtime, shell-side equivalent of
# `realization.nix` (ADR-0028): it fully realizes the account from identity.json + the safe-set
# grant (password, authorizedKeys, GECOS, the CLAMPED safe groups) so a greeter user realizes
# IDENTICALLY to a build-time one — the portable-user north star: same identity, any seat, same
# experience.
{
  lib,
  privilegedGroups,
  featureGroups,
  safeSet,
  greeterGrants,
  tier1EvalConfig,
  renderNixConfig,
  identityFile,
}:
let
  # The safe set's group memberships — the system-side effect greeterGrants confers (ADR-0026).
  # For the safe set `["gui"]` this is gui's input groups; they form the standing greeter-seat
  # baseline this module declares + `provision` enrolls each account into.
  baselineGroups = lib.unique (lib.concatMap (f: featureGroups.${f} or [ ]) safeSet);
  enrolledGroups = baselineGroups ++ [ "greeter-users" ];

  # The Tier-1 restricted-eval posture (ADR-0030), rendered to a NIX_CONFIG body the greeter
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

  # The four shipped programs, one per file (the canonical mechanism + the replaceable UI). Each is
  # a writeShellApplication closed over only what it needs; bind orchestrates the other three.
  authScript = import ./greeter/auth.nix { inherit pkgs identityFile; };
  unlockScript = import ./greeter/unlock.nix { inherit pkgs; };
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
      unlockScript
      ;
    inherit (cfg)
      tier
      trustedSigners
      homeBuilder
      secretProvisioning
      ;
    exposed = config.custom.host.exposed;
  };
in
{
  options.custom.greeter = {
    enable = lib.mkEnableOption ''
      the contract's reference runtime greeter (greetd + the eval-free bind→safe-set-grant→provision
      flow, ADR-0022/0024). A seat host enables it; a headless host simply does not (incapacity, not
      a ban). The contract evaluates with this module present but unbound exactly as with the platform
      interface unbound (ADR-0024 litmus test)'';

    tier = lib.mkOption {
      type = lib.types.enum [
        "tier1"
        "tier2"
      ];
      default = "tier1";
      description = ''
        The trust tier this seat binds at (host POLICY, ADR-0022). `tier1` (semi-trusted, own
        identities): the repo must be signed by a host-trusted key, the home is persisted, and
        eval runs under the contract-pinned restricted-eval posture (ADR-0030, `tier1EvalConfig`) to
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
        Read-only introspection of the Tier-1 restricted-eval posture (ADR-0030): the canonical Nix
        settings the greeter hands the `homeBuilder` as NIX_CONFIG when it builds a host-signed home.
        Fixed to the contract's `tier1EvalConfig` — `accept-flake-config = false` (the repo cannot
        widen its own eval, ADR-0027), `restrict-eval`, no IFD, and a sandboxed build. A host may add
        restrictions in its homeBuilder, never remove these.
      '';
    };

    trustedSigners = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Tier-1 allowed signers: SSH public keys whose signature over a user repo marks it
        semi-trusted (ADR-0022, ADR-0027). This is the host's trust BINDING and the SOLE Tier-1
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
        Host BINDING (ADR-0024 "the host supplies only bindings"): a command invoked as
        `homeBuilder <src> <username>` that evaluates the user's home THROUGH the contract
        (bindUserModule { grants = greeterGrants; … }) under the tier's restricted-eval posture
        and prints the built home-activation package path. It is null by default because building a
        real home needs home-manager, which the contract does not depend on (ADR-0020); the host
        supplies it, exactly as it supplies the platform and display bindings. The reference greeter
        ships everything else — greetd wiring, the eval-free auth ordering, the runtime
        provisioning helper, and session selection — package-free at the flake level.
      '';
    };

    desktops = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            type = lib.mkOption {
              type = lib.types.enum [
                "wayland"
                "x11"
              ];
              default = "wayland";
              description = "The session type of this desktop (sets XDG_SESSION_TYPE).";
            };
            command = lib.mkOption {
              type = lib.types.str;
              description = "The command that launches this desktop's session (its `wayland-sessions`/`xsessions` Exec).";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          gnome.command = "''${pkgs.gnome-session}/bin/gnome-session";
          plasma = { type = "wayland"; command = "''${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland"; };
        }
      '';
      description = ''
        Host BINDING (ADR-0029): the desktops this seat offers, keyed by the free-form name a user
        requests via `contract.requests.gui.desktop`. The contract ships no desktop (ADR-0020); the
        seat enables its DEs and binds each one's session-entry command here, exactly as a display
        manager launches them. A user's requested name that is not offered degrades to `defaultDesktop`.
      '';
    };

    defaultDesktop = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "The `desktops` name to launch when the user requests none, or requests one this seat does not offer (ADR-0029).";
    };

    secretProvisioning = lib.mkOption {
      description = ''
        Greeter secret provisioning (ADR-0031, issue #10): on a TRUSTED Tier-1 seat, unlock the user's
        OWN age key from their repo with a passphrase so their home sops decrypt at a roaming login.
        Off by default and a host BINDING (the seat asserts it is trusted to hold the user's plaintext
        for the session). REFUSED on an exposed host (ADR-0015) and at tier2 (secret-free). Distinct
        from contract secret-features (`signing`), which stay build-time via the safe set.
      '';
      default = { };
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "unlocking the user's age key at a greeter login (trusted Tier-1 seats only)";
          method = lib.mkOption {
            type = lib.types.enum [
              "passphrase"
              "escrow"
            ];
            default = "passphrase";
            description = ''
              Where the wrapped age key comes from (ADR-0031). `passphrase` (issue #10): a key wrapped in
              the user's repo, unlocked by a passphrase — portable, no infra. `escrow` (issue #11): the
              wrapped key lives off-repo and is obtained via the host's `keyFetcher` binding (e.g. fetched
              from the user's server after a PHONE approval), removing the public offline-brute-forceable
              blob; the fetched key is still passphrase-unlocked (two factors: gate + passphrase).
            '';
          };
          keyFetcher = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.oneOf [
                lib.types.str
                lib.types.path
                lib.types.package
              ]
            );
            default = null;
            description = ''
              Host BINDING for method = "escrow" (ADR-0031 update, issue #11): a command invoked as
              `keyFetcher <username>` that obtains the user's wrapped age key and prints it to STDOUT
              (bind captures it to a private file — binary-safe). The contract ships the SEAM, never a
              wire protocol — exactly like `homeBuilder` — so the host binds whatever release mechanism it
              runs (the reference example composes OpenBao one-time wrapping + an ntfy phone approval, #13;
              it must use a confidential channel and stream bytes, not a shell var). Null ⇒ no fetcher.
            '';
          };
          requireSecrets = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              If true, FAIL the login when secret provisioning is enabled but no key could be obtained
              (escrow server unreachable, no wrapped key, …) — for workloads that must not run secret-free.
              Default false: fail CLOSED on secrets but never on the login (ADR-0031 update) — a missing
              key degrades to a secret-free session, which cannot leak. There is deliberately NO in-repo
              passphrase fallback for escrow (that would be a downgrade attack).
            '';
          };
          separatePassphrase = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Prompt a SEPARATE unlock passphrase (recommended) rather than reusing the login password.
              The login password also backs `hashedPassword` and the wrapped key is public/offline-
              brute-forceable, so decoupling lets the key be stronger than the login secret.
            '';
          };
          wrappedKeyName = lib.mkOption {
            type = lib.types.str;
            default = "contract-key.enc";
            description = "Filename in the user repo of the passphrase-wrapped age identity (see contract-greeter-unlock for the wrapping).";
          };
          keyFile = lib.mkOption {
            type = lib.types.str;
            default = ".config/sops/age/keys.txt";
            description = "Home-relative path the unlocked age identity is installed to (sops-nix's default age key path).";
          };
        };
      };
    };

    grants = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.bool);
      readOnly = true;
      default = greeterGrants;
      description = ''
        Read-only introspection of the runtime grant a greeter login receives — fixed to
        `greeterGrants` (default-open over the safe set, ADR-0024 condition 3). It cannot be
        widened here; the greeter auto-grants every runtime-eligible feature and nothing more.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Secret provisioning is indefensible on an exposed host — the seat sees the user's decrypted
    # secrets while it activates the home (ADR-0031, gated on the ADR-0015 exposed-host ban). bind
    # also refuses at runtime; this makes a misconfigured seat a clear eval error, not a login surprise.
    assertions = [
      {
        assertion = cfg.secretProvisioning.enable -> !config.custom.host.exposed;
        message = "custom.greeter.secretProvisioning is enabled on exposed host '${config.networking.hostName}' — an exposed/agent host must never hold the user's key material (ADR-0015, ADR-0031)";
      }
      {
        assertion =
          (cfg.secretProvisioning.enable && cfg.secretProvisioning.method == "escrow")
          -> cfg.secretProvisioning.keyFetcher != null;
        message = "custom.greeter.secretProvisioning.method = \"escrow\" needs a keyFetcher host binding (ADR-0031 issue #11)";
      }
    ];

    # greetd runs the bind orchestrator as the seat's login program. The default_session command
    # is mkDefault so a host can substitute regreet/its own UI (the replaceable half) while the
    # binding scripts below stay canonical.
    services.greetd = {
      enable = true;
      settings.default_session.command = lib.mkDefault "${bindScript}/bin/contract-greeter-bind";
    };

    # The greeter-seat baseline (ADR-0026): the safe set's group memberships + a `greeter-users`
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
      unlockScript
    ];
  };
}
