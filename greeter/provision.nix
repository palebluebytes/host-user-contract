# (7) the privileged runtime-provisioning helper: the shell-side realization.nix (ADR-0012).
# Usage: contract-greeter-provision <username> <identity.json> <activation-package> <tier>
# NixOS users are declarative, and a greeter user is never built into the system (ADR-0010), so
# realization.nix never runs for them — this IS their realization, run at login. It materializes
# the (Tier-1 persisted) account and FULLY realizes it from identity.json + the safe-set grant:
# password (the same hash auth verified ⇒ PAM works), authorizedKeys, GECOS, and the user's safe
# declared groups plus the greeter-seat baseline. Then it activates the built home AS the user.
# Tier-2 (ephemeral) is deferred. Runs as root (greetd's pre-session context); it drops to the user
# for activation. The activated session is secret-free: the contract handles no secrets beyond the
# login credential.
#
# It is the RUNTIME ADAPTER over accountPlan (issue #31), the twin of realization.nix's build-time
# adapter. It owns none of accountPlan's identity→account DATA: the greeter renders accountPlan's
# grant-side to a build-time plan (`provisionPlan`) — the privileged-group CLAMP SET and the
# greeter-seat baseline groups (both from the injected grantLib, so identical to the build-time
# side) plus the identity FIELD-NAME projection (from identity.nix) — and this script reads all of
# those from the plan; no privileged group, no baseline group, and no identity field name is
# hardcoded here. What it does REPRODUCE is accountPlan's four-field COMBINING RULE, in jq: a shell
# login cannot call the Nix function and the identity is known only at runtime, so the rule (not its
# inputs) is necessarily expressed twice. The single-sourced clamp SET makes a hostile identity.json
# unable to smuggle a privileged group at runtime; the greeter-provision VM asserts the realized
# account matches the build-time accountPlan record FIELD FOR FIELD, guarding the reproduced rule
# against drift by construction rather than trusting the two jq/Nix spellings to stay in step.
{
  pkgs,
  provisionPlan,
}:
let
  # accountPlan's grant-side + clamp + identity field projection, rendered to data at BUILD TIME
  # (issue #31): `{ identityFields; privilegedGroups; enrolledGroups }`. Serializable because the
  # plan is a neutral record (ADR-0012). The script reads it back with jq — no field name or clamp
  # list is hardcoded in the shell.
  planFile = pkgs.writeText "contract-greeter-provision-plan.json" (builtins.toJSON provisionPlan);
in
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
    plan=${planFile}

    [ "$(id -u)" = 0 ] || { echo "provision: must run as root" >&2; exit 1; }
    [ -f "$identity" ] || { echo "provision: no identity.json at '$identity'" >&2; exit 1; }
    [ -x "$activation/activate" ] || { echo "provision: '$activation' is not a home-activation package" >&2; exit 1; }

    case "$tier" in
      tier1) : ;; # persisted (a normal account with a real home, ADR-0006)
      tier2) echo "provision: tier2 (ephemeral) provisioning is deferred (ADR-0006)" >&2; exit 1 ;;
      *) echo "provision: unknown tier '$tier'" >&2; exit 1 ;;
    esac

    home="/home/$username"
    if ! id -u "$username" >/dev/null 2>&1; then
      useradd --create-home --home-dir "$home" --shell /run/current-system/sw/bin/bash \
        --user-group "$username"
    fi

    # --- runtime adapter over accountPlan (ADR-0012, issue #31) ---
    # Reproduce accountPlan's (identity + safe-set grant) ⇒ account record from the BUILD-TIME
    # rendered plan: GECOS ← name; hashedPassword verbatim; authorizedKeys = the primary sshKey
    # (dropped when empty) then trustedKeys; extraGroups = the self-declared groups with the plan's
    # privileged set CLAMPED out, unioned with the greeter-seat baseline. Field names, the clamp set,
    # and the baseline all come from the plan (single-sourced through grantLib/identityOptions) — no
    # bespoke jq field paths, no hand-listed privileged groups.
    record=$(jq -n --slurpfile plan "$plan" --slurpfile id "$identity" '
      $plan[0] as $p
      | $id[0] as $i
      | $p.identityFields as $f
      | {
          description: ($i[$f.name] // ""),
          hashedPassword: ($i[$f.hashedPassword] // ""),
          authorizedKeys: ([ ($i[$f.sshKey] // "") ] | map(select(. != "")))
                          + ($i[$f.trustedKeys] // []),
          extraGroups: ((($i[$f.extraGroups] // []) - $p.privilegedGroups) + $p.enrolledGroups | unique)
        }')

    # GECOS = the account record's description.
    name=$(jq -r '.description // empty' <<<"$record")
    [ -n "$name" ] && usermod -c "$name" "$username"

    # Password = the record's hashedPassword (the same value auth verified) ⇒ PAM works.
    hash=$(jq -r '.hashedPassword // empty' <<<"$record")
    [ -n "$hash" ] && printf '%s:%s\n' "$username" "$hash" | chpasswd -e

    # Groups = the record's (clamped ∪ baseline) set, restricted to groups that exist on the seat
    # (the greeter-seat baseline is pre-realized declaratively; a stray name is skipped, not created).
    readarray -t want < <(jq -r '.extraGroups[]?' <<<"$record")
    add=()
    for g in "''${want[@]}"; do getent group "$g" >/dev/null 2>&1 && add+=("$g"); done
    [ "''${#add[@]}" -gt 0 ] && usermod -aG "$(IFS=,; echo "''${add[*]}")" "$username"

    # authorizedKeys = the record's SSH login keys (sshKey + trustedKeys).
    ssh_dir="$home/.ssh"
    install -d -o "$username" -g "$username" -m 700 "$ssh_dir"
    jq -r '.authorizedKeys[]?' <<<"$record" > "$ssh_dir/authorized_keys"
    chown "$username:$username" "$ssh_dir/authorized_keys"
    chmod 600 "$ssh_dir/authorized_keys"

    install -d -o "$username" -g "$username" "$home"

    # Activate the built home AS the user — the runtime equivalent of the declarative
    # home-manager activation a build-time user gets, run now instead of at switch time.
    runuser -u "$username" -- env HOME="$home" "$activation/activate"
    echo "provision: $username realized (tier=$tier) + home activated" >&2
  '';
}
