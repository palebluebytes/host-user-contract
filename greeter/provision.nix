# (7) the privileged runtime-provisioning helper: the shell-side realization.nix (ADR-0028).
# Usage: contract-greeter-provision <username> <identity.json> <activation-package> <tier>
# NixOS users are declarative, and a greeter user is never built into the system (ADR-0026), so
# realization.nix never runs for them — this IS their realization, run at login. It materializes
# the (Tier-1 persisted) account and FULLY realizes it from identity.json + the safe-set grant:
# password (the same hash auth verified ⇒ PAM works), authorizedKeys, GECOS, and the user's safe
# declared groups — reproducing realization.nix's privileged-group CLAMP so a hostile identity.json
# still cannot smuggle a privileged group at runtime — plus enrollment in the greeter-seat
# baseline. Then it activates the built home AS the user. Tier-2 (ephemeral) is deferred. Runs as
# root (greetd's pre-session context); it drops to the user for activation.
{
  pkgs,
  lib,
  privilegedGroups,
  enrolledGroups,
}:
pkgs.writeShellApplication {
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
}
