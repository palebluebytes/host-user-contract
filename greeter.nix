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
#   2. fetch SOURCE ONLY (nix flake prefetch, no outputs)  — no user Nix evaluated yet
#   3. authenticate EVAL-FREE (jq identity.json: password + Tier-1 signature, ADR-0027) — CANONICAL
#   4. classify the tier                                   — host policy (custom.greeter.tier)
#   5/6. evaluate + build the home under restricted eval   — host BINDING (homeBuilder)
#   7. provision: FULLY realize the account (shell-side realization.nix) + activate the home — CRUX
#   8. launch the session (gui.session selects the type; the host binds the backend)  — ADR-0026
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
  identityFile,
}:
let
  # The safe set's group memberships — the system-side effect greeterGrants confers (ADR-0026).
  # For the safe set `["gui"]` this is gui's input groups; they form the standing greeter-seat
  # baseline this module declares + `provision` enrolls each account into.
  baselineGroups = lib.unique (lib.concatMap (f: featureGroups.${f} or [ ]) safeSet);
  enrolledGroups = baselineGroups ++ [ "greeter-users" ];
in
{
  config,
  pkgs,
  ...
}:
let
  cfg = config.custom.greeter;
  sessionCmd =
    t:
    let
      v = cfg.session.${t};
    in
    if v == null then "" else v;

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
      waylandCmd=${lib.escapeShellArg (sessionCmd "wayland")}
      x11Cmd=${lib.escapeShellArg (sessionCmd "x11")}
      defaultType=${lib.escapeShellArg cfg.session.default}

      # The bound home may override the seat default by dropping its requested type in $home.
      if [ -f "$home/.contract-session" ]; then
        type=$(cat "$home/.contract-session")
      else
        type=$defaultType
      fi

      case "$type" in
        wayland) backend=$waylandCmd ;;
        x11) backend=$x11Cmd ;;
        *) echo "session: unknown type '$type'" >&2; exit 1 ;;
      esac
      [ -n "$backend" ] || { echo "session: no $type session backend bound (custom.greeter.session.$type)" >&2; exit 1; }

      exec runuser -u "$username" -- env HOME="$home" XDG_SESSION_TYPE="$type" bash -c "$backend"
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

      [ -n "$homeBuilder" ] || {
        echo "greeter: no homeBuilder bound — a seat host must set custom.greeter.homeBuilder" >&2
        echo "         (building a real home needs home-manager, which the host supplies)" >&2
        exit 1
      }

      # 1. prompt — the replaceable UI half.
      printf 'flake URL: ' >&2; read -r flake
      printf 'username: ' >&2; read -r username
      printf 'password: ' >&2; stty -echo 2>/dev/null || true; read -r password; stty echo 2>/dev/null || true; printf '\n' >&2

      # 2. fetch SOURCE ONLY — no flake OUTPUT is evaluated, so no user Nix has run yet.
      src=$(nix flake prefetch --json --refresh "$flake" | jq -r .storePath)

      # 3. authenticate EVAL-FREE (jq + crypt + Tier-1 signature) before any user Nix.
      printf '%s\n' "$password" | contract-greeter-auth "$src" "$username" "$tier" "$signers"

      # 5/6. evaluate + build the home THROUGH the contract under restricted eval — host binding.
      activation=$("$homeBuilder" "$src" "$username")

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
        eval is restricted to guard accidents — built now. `tier2` (untrusted, anyone): ephemeral
        home, hardened eval — designed-for but DEFERRED, so the provisioning helper refuses it today.
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

    session = {
      wayland = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Host BINDING (ADR-0026 step 8): the command that launches a Wayland session (a compositor)
          for a provisioned user. null ⇒ this seat offers no Wayland session. The contract ships no
          compositor (ADR-0020); the seat picks sway/Hyprland/Plasma, just as it binds the display
          backend for the build-time path. A user's home may override per-login via `~/.contract-session`.
        '';
      };
      x11 = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host BINDING (ADR-0026 step 8): the command that launches an X11 session. null ⇒ no X11 session on this seat.";
      };
      default = lib.mkOption {
        type = lib.types.enum [
          "wayland"
          "x11"
        ];
        default = "wayland";
        description = "The session type to launch when the bound home does not request one (no `~/.contract-session`).";
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
