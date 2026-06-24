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
# The flow (ADR-0022 "data before code" — authenticate on inert data before running any Nix):
#   1. prompt (flake URL, username, password)              — replaceable UI
#   2. fetch SOURCE + input closure (nix flake archive)   — no outputs evaluated, no user Nix yet
#   3. authenticate EVAL-FREE (jq identity.json: password + Tier-1 signature, ADR-0027) — CANONICAL
#   4. classify the tier                                   — host policy (custom.greeter.tier)
#   5/6. build the home under the PINNED restricted-eval posture (ADR-0030) — host BINDING (homeBuilder)
#   7. provision: FULLY realize the account (shell-side realization.nix) + activate the home — CRUX
#   8. launch the session — the user's chosen DESKTOP (the seat offers desktops, host binds) — ADR-0029
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
  # The desktops this seat offers, baked into a shell `case` the launcher resolves the user's
  # requested desktop against (ADR-0029). Each arm sets the session type + the launch command.
  desktopArms = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: d:
      "        ${lib.escapeShellArg name}) dtype=${lib.escapeShellArg d.type}; dcmd=${lib.escapeShellArg d.command} ;;"
    ) cfg.desktops
  );

  # --- (3) the eval-free auth: jq over the inert identity.json, zero lines of user Nix ---
  # Usage: contract-greeter-auth <src> <username> <tier> <allowed-signers-file>  (password on stdin)
  # The CANONICAL, mandatory mechanism (ADR-0024 condition 1). It reads only data (`jq`) and
  # re-hashes the password with libc crypt (via perl, which covers yescrypt/sha512crypt exactly
  # as /etc/shadow does) — it never evaluates the user's flake.
  authScript = pkgs.writeShellApplication {
    name = "contract-greeter-auth";
    runtimeInputs = [
      pkgs.jq
      pkgs.perl
      pkgs.openssh
    ];
    text = ''
      src=$1
      username=$2
      tier=$3
      signers=$4
      identity="$src/${identityFile}"

      [ -f "$identity" ] || { echo "auth: no ${identityFile} in repo source" >&2; exit 1; }

      # The username the caller logs in as must be the one the repo claims (no impersonation).
      claimed=$(jq -r '.username // empty' "$identity")
      [ "$claimed" = "$username" ] || { echo "auth: username mismatch (repo claims '$claimed')" >&2; exit 1; }

      # Password: verify against identity.json.hashedPassword with libc crypt — eval-free.
      stored=$(jq -r '.hashedPassword // empty' "$identity")
      [ -n "$stored" ] || { echo "auth: identity.json has no hashedPassword" >&2; exit 1; }
      read -r password
      computed=$(perl -e 'print crypt($ARGV[0], $ARGV[1])' "$password" "$stored")
      [ "$computed" = "$stored" ] || { echo "auth: password mismatch" >&2; exit 1; }

      # Tier 1 (semi-trusted): the repo must be SIGNED by a HOST-pinned key (ADR-0022, ADR-0027).
      # We verify an SSH signature over a manifest of the tree (the whole config is signed, not
      # just identity.json) against the host's operator-pinned trustedSigners ALONE. The host is
      # the SOLE Tier-1 trust anchor — a repo cannot vouch for its own tier (a repo naming and
      # signing with its own key would self-certify, i.e. Tier 2's threat model). Note
      # identity.json.trustedKeys is SSH LOGIN keys (realization → authorizedKeys), never consulted here.
      if [ "$tier" = tier1 ]; then
        [ -s "$signers" ] || { echo "auth: tier1 requires host-pinned trusted signers" >&2; exit 1; }
        [ -f "$src/contract.sig" ] || { echo "auth: tier1 requires a repo signature (contract.sig)" >&2; exit 1; }
        manifest=$(cd "$src" && find . -type f ! -name contract.sig -print0 | sort -z \
          | xargs -0 sha256sum)
        printf '%s' "$manifest" \
          | ssh-keygen -Y verify -f "$signers" -I "$username" -n contract -s "$src/contract.sig" \
          || { echo "auth: tier1 signature verification failed" >&2; exit 1; }
      fi

      echo "auth: $username authenticated (tier=$tier), zero user Nix evaluated" >&2
    '';
  };

  # --- (7) the privileged runtime-provisioning helper: the shell-side realization.nix (ADR-0028) ---
  # Usage: contract-greeter-provision <username> <identity.json> <activation-package> <tier>
  # NixOS users are declarative, and a greeter user is never built into the system (ADR-0026), so
  # realization.nix never runs for them — this IS their realization, run at login. It materializes
  # the (Tier-1 persisted) account and FULLY realizes it from identity.json + the safe-set grant:
  # password (the same hash auth verified ⇒ PAM works), authorizedKeys, GECOS, and the user's safe
  # declared groups — reproducing realization.nix's privileged-group CLAMP so a hostile identity.json
  # still cannot smuggle a privileged group at runtime — plus enrollment in the greeter-seat
  # baseline. Then it activates the built home AS the user. Tier-2 (ephemeral) is deferred. Runs as
  # root (greetd's pre-session context); it drops to the user for activation.
  provisionScript = pkgs.writeShellApplication {
    name = "contract-greeter-provision";
    runtimeInputs = [
      pkgs.jq
      pkgs.shadow
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      username=$1
      identity=$2
      activation=$3
      tier=$4

      [ "$(id -u)" = 0 ] || { echo "provision: must run as root" >&2; exit 1; }
      [ -f "$identity" ] || { echo "provision: no identity.json at '$identity'" >&2; exit 1; }
      [ -x "$activation/activate" ] || { echo "provision: '$activation' is not a home-activation package" >&2; exit 1; }

      case "$tier" in
        tier1) : ;; # persisted (a normal account with a real home, ADR-0022)
        tier2) echo "provision: tier2 (ephemeral) provisioning is deferred (ADR-0022)" >&2; exit 1 ;;
        *) echo "provision: unknown tier '$tier'" >&2; exit 1 ;;
      esac

      home="/home/$username"
      if ! id -u "$username" >/dev/null 2>&1; then
        useradd --create-home --home-dir "$home" --shell /run/current-system/sw/bin/bash \
          --user-group "$username"
      fi

      # --- shell-side realization.nix (ADR-0028): identity + safe-set grant ⇒ the account ---
      # GECOS = name.
      name=$(jq -r '.name // empty' "$identity")
      [ -n "$name" ] && usermod -c "$name" "$username"

      # Password = identity.hashedPassword (the same value auth verified) ⇒ PAM works.
      hash=$(jq -r '.hashedPassword // empty' "$identity")
      [ -n "$hash" ] && printf '%s:%s\n' "$username" "$hash" | chpasswd -e

      # Groups: clamp privileged groups out of the user's self-declared extraGroups (untrusted
      # input — reproduce realization.nix's safeDeclared), then enroll into the safe declared
      # groups + the greeter-seat baseline (the safe-set grant groups + the greeter-users marker),
      # restricted to groups that exist on the seat.
      privileged=(${lib.concatStringsSep " " privilegedGroups})
      baseline=(${lib.concatStringsSep " " enrolledGroups})
      readarray -t declared < <(jq -r '.extraGroups[]? // empty' "$identity")
      want=()
      for g in "''${declared[@]}"; do
        clamp=0
        for p in "''${privileged[@]}"; do [ "$g" = "$p" ] && clamp=1; done
        [ "$clamp" = 0 ] && want+=("$g")
      done
      want+=("''${baseline[@]}")
      add=()
      for g in "''${want[@]}"; do getent group "$g" >/dev/null 2>&1 && add+=("$g"); done
      [ "''${#add[@]}" -gt 0 ] && usermod -aG "$(IFS=,; echo "''${add[*]}")" "$username"

      # authorizedKeys = sshKey + trustedKeys (the user's SSH LOGIN keys).
      ssh_dir="$home/.ssh"
      install -d -o "$username" -g "$username" -m 700 "$ssh_dir"
      {
        sshKey=$(jq -r '.sshKey // empty' "$identity"); [ -n "$sshKey" ] && printf '%s\n' "$sshKey"
        jq -r '.trustedKeys[]? // empty' "$identity"
      } > "$ssh_dir/authorized_keys"
      chown "$username:$username" "$ssh_dir/authorized_keys"
      chmod 600 "$ssh_dir/authorized_keys"

      # Activate the built home AS the user — the runtime equivalent of the declarative
      # home-manager activation a build-time user gets, run now instead of at switch time.
      install -d -o "$username" -g "$username" "$home"
      runuser -u "$username" -- env HOME="$home" "$activation/activate"
      echo "provision: $username realized (tier=$tier) + home activated" >&2
    '';
  };

  # --- (8) the session launcher: the greeter SELECTS the type, the HOST binds the backend ---
  # Usage: contract-greeter-session <username> <home-dir>
  # ADR-0026: the contract decides the session TYPE (from the bound home's gui.session, surfaced
  # here as an optional `$home/.contract-session` the home may write, else the seat's default);
  # the host BINDS the actual compositor/Xorg per type (custom.greeter.session.{wayland,x11}),
  # exactly as the display backend is host-bound. The contract ships no compositor (ADR-0020).
  sessionScript = pkgs.writeShellApplication {
    name = "contract-greeter-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.bash
    ];
    text = ''
            username=$1
            home=$2
            defaultDesktop=${lib.escapeShellArg cfg.defaultDesktop}

            # Resolve a desktop NAME to its session type + launch command (the seat's offered desktops).
            resolve() {
              case "$1" in
      ${desktopArms}
                *) return 1 ;;
              esac
            }

            # The user's chosen desktop is surfaced from their home (~/.contract-desktop, materialised from
            # contract.requests.gui.desktop); absent ⇒ the seat default.
            if [ -f "$home/.contract-desktop" ]; then
              want=$(cat "$home/.contract-desktop")
            else
              want=$defaultDesktop
            fi

            # An un-offered/unknown desktop degrades to the seat default — never breaks the login (ADR-0029).
            dtype=""; dcmd=""
            if ! resolve "$want"; then
              echo "session: desktop '$want' not offered by this seat; using default '$defaultDesktop'" >&2
              resolve "$defaultDesktop" || { echo "session: no default desktop offered (custom.greeter.desktops/defaultDesktop)" >&2; exit 1; }
            fi
            [ -n "$dcmd" ] || { echo "session: resolved desktop has no command" >&2; exit 1; }

            # The session must run AS the user, in a SEAT session, for the compositor/DE/Xorg to get DRM
            # and a systemd-user instance — which is greetd's job (it creates the logind seat session and
            # runs this command as the user). So when already the user (greetd's model) exec in place; only
            # drop privs with runuser when invoked by the root orchestrator (which is NOT a seat session —
            # that path suits headless/marker backends, not a real GPU session). ADR-0026/0029 step 8.
            if [ "$(id -un)" = "$username" ]; then
              exec env HOME="$home" XDG_SESSION_TYPE="$dtype" bash -c "$dcmd"
            else
              exec runuser -u "$username" -- env HOME="$home" XDG_SESSION_TYPE="$dtype" bash -c "$dcmd"
            fi
    '';
  };

  # --- the orchestrator greetd runs: ties the eval-free ordering together (replaceable UI) ---
  # The prompt loop here is the reference UI; a host may swap regreet/its own front end as long
  # as it preserves the ordering. The home BUILD (step 5/6) is delegated to the host's
  # `homeBuilder` binding — it needs home-manager, which the contract does not ship (ADR-0020).
  bindScript = pkgs.writeShellApplication {
    name = "contract-greeter-bind";
    runtimeInputs = [
      pkgs.nix
      pkgs.jq
      pkgs.coreutils
      authScript
      provisionScript
      sessionScript
    ];
    text = ''
      tier=${lib.escapeShellArg cfg.tier}
      signers=${
        if cfg.trustedSigners == [ ] then
          "/var/empty/contract-greeter-signers"
        else
          pkgs.writeText "contract-greeter-allowed-signers" (
            lib.concatMapStringsSep "\n" (k: "* ${k}") cfg.trustedSigners
          )
      }
      homeBuilder=${lib.escapeShellArg (toString cfg.homeBuilder)}

      # The Tier-1 restricted-eval posture the contract PINS (ADR-0030): a host-signed repo is still
      # built under a restricted eval it cannot widen. Rendered from the contract's canonical
      # tier1EvalConfig — single-sourced, conformance-checked. accept-flake-config=false is applied
      # to the fetch too, so the repo's own nixConfig is ignored even while locking.
      tier1EvalConfig=${lib.escapeShellArg tier1NixConfig}

      [ -n "$homeBuilder" ] || {
        echo "greeter: no homeBuilder bound — a seat host must set custom.greeter.homeBuilder" >&2
        echo "         (building a real home needs home-manager, which the host supplies)" >&2
        exit 1
      }

      # 1. prompt — the replaceable UI half.
      printf 'flake URL: ' >&2; read -r flake
      printf 'username: ' >&2; read -r username
      printf 'password: ' >&2; stty -echo 2>/dev/null || true; read -r password; stty echo 2>/dev/null || true; printf '\n' >&2

      # 2. fetch the SOURCE + its whole INPUT CLOSURE — no flake OUTPUT is evaluated, so no user Nix
      # has run yet — and the closure is warmed so the step-5/6 restricted-eval build needs no
      # eval-time network (restrict-eval would otherwise block it). The repo's nixConfig is ignored
      # even here (accept-flake-config=false), so it cannot influence the fetch/lock.
      src=$(nix --option accept-flake-config false flake archive --json --refresh "$flake" | jq -r .path)

      # 3. authenticate EVAL-FREE (jq + crypt + Tier-1 signature) before any user Nix.
      printf '%s\n' "$password" | contract-greeter-auth "$src" "$username" "$tier" "$signers"

      # 5/6. evaluate + build the home THROUGH the contract, under the contract-pinned restricted-eval
      # posture (ADR-0030) — handed to the host's homeBuilder as NIX_CONFIG so a naive `nix build`
      # binding inherits the floor; it augments the seat's nix.conf (experimental-features survive).
      activation=$(env NIX_CONFIG="$tier1EvalConfig" "$homeBuilder" "$src" "$username")

      # 7. FULLY realize the account (shell-side realization.nix) + activate the home.
      contract-greeter-provision "$username" "$src/${identityFile}" "$activation" "$tier"

      # 8. launch the session (the type is selected here; the host-bound backend renders it).
      exec contract-greeter-session "$username" "/home/$username"
    '';
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
    ];
  };
}
