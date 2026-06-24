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
# (1) and (3) are enforced here in the auth script + the fixed greeterGrants; (2) is the build
# step, which is the host's `homeBuilder` BINDING (building a real home needs home-manager,
# which the contract does not depend on — exactly as the platform/display bindings are host-side).
#
# The flow (ADR-0022 "data before code" — authenticate on inert data before running any Nix):
#   1. prompt (flake URL, username, password)              — replaceable UI
#   2. fetch SOURCE ONLY (nix flake prefetch, no outputs)  — no user Nix evaluated yet
#   3. authenticate EVAL-FREE (jq identity.json: password + Tier-1 signature)  — CANONICAL
#   4. classify the tier                                   — host policy (custom.greeter.tier)
#   5/6. evaluate + build the home under restricted eval   — host BINDING (homeBuilder)
#   7/8. provision: materialize the account + activate the home + start the session  — the CRUX
{
  lib,
  greeterGrants,
  identityFile,
}:
{
  config,
  pkgs,
  ...
}:
let
  cfg = config.custom.greeter;

  # --- (3) the eval-free auth: jq over the inert identity.json, zero lines of user Nix ---
  # Usage: contract-greeter-auth <src> <username> <tier> <allowed-signers-file>  (password on stdin)
  # The CANONICAL, mandatory mechanism (ADR-0024 condition 1). It reads only data (`jq`) and
  # re-hashes the password with libc crypt (via perl, which covers yescrypt/sha512crypt exactly
  # as /etc/shadow does) — it never evaluates the user's flake. Tier-1 additionally verifies an
  # SSH signature over the repo's identity against the host-pinned allowed signers.
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

  # --- (7/8) the privileged runtime-provisioning helper: the genuinely novel crux (ADR-0022) ---
  # Usage: contract-greeter-provision <username> <activation-package> <tier>
  # NixOS users are declarative (build-time). This materializes the account and activates the
  # built home OUTSIDE the build-time model, at login: it creates (Tier-1: persisted) the user
  # if absent, then runs the home-manager activation package AS that user. Tier-2 (ephemeral,
  # tmpfs home wiped on logout) is the deferred knob — the helper refuses it today rather than
  # pretending to provide it. Runs as root (greetd's pre-session context); it drops to the user
  # for activation.
  provisionScript = pkgs.writeShellApplication {
    name = "contract-greeter-provision";
    runtimeInputs = [
      pkgs.shadow
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      username=$1
      activation=$2
      tier=$3

      [ "$(id -u)" = 0 ] || { echo "provision: must run as root" >&2; exit 1; }
      [ -x "$activation/activate" ] || { echo "provision: '$activation' is not a home-activation package" >&2; exit 1; }

      case "$tier" in
        tier1) persist=1 ;;
        tier2) echo "provision: tier2 (ephemeral) provisioning is deferred (ADR-0022)" >&2; exit 1 ;;
        *) echo "provision: unknown tier '$tier'" >&2; exit 1 ;;
      esac

      home="/home/$username"
      if ! id -u "$username" >/dev/null 2>&1; then
        # Tier 1 is persisted: a normal account with a real home (ADR-0022 "persistence is a
        # tier property"). The greeter grants only the safe set, so no privileged group is added.
        useradd --create-home --home-dir "$home" --shell /run/current-system/sw/bin/bash \
          --user-group "$username"
      fi
      [ "$persist" = 1 ] # (tier2/ephemeral would mount a tmpfs home here)

      # Activate the built home AS the user — this is the runtime equivalent of the declarative
      # home-manager activation a build-time user gets, run now instead of at switch time.
      install -d -o "$username" -g "$username" "$home"
      runuser -u "$username" -- env HOME="$home" "$activation/activate"
      echo "provision: $username provisioned (tier=$tier, persisted) and home activated" >&2
    '';
  };

  # --- the orchestrator greetd runs: ties the eval-free ordering together (replaceable UI) ---
  # The prompt loop here is the reference UI; a host may swap regreet/its own front end as long
  # as it preserves the ordering below. The home BUILD (step 5/6) is delegated to the host's
  # `homeBuilder` binding — it needs home-manager, which the contract does not ship (ADR-0020).
  bindScript = pkgs.writeShellApplication {
    name = "contract-greeter-bind";
    runtimeInputs = [
      pkgs.nix
      pkgs.jq
      pkgs.coreutils
      authScript
      provisionScript
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
      home=$("$homeBuilder" "$src" "$username")

      # 7/8. provision the account + activate the home + start the session (the novel crux).
      exec contract-greeter-provision "$username" "$home" "$tier"
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
        semi-trusted (ADR-0022). This is the host's trust BINDING — empty means no repo is Tier-1
        on this seat. The matching public key also lives in the user's identity.json.trustedKeys.
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
        ships everything else — greetd wiring, the eval-free auth ordering, and the runtime
        provisioning helper — package-free at the flake level.
      '';
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

    # The bind/auth/provision scripts are on PATH so the provisioning helper (and a host's own
    # greeter UI) can call them; the helper is the privileged crux greetd invokes pre-session.
    environment.systemPackages = [
      bindScript
      authScript
      provisionScript
    ];
  };
}
