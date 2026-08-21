# (7) the privileged runtime-provisioning helper: the shell-side realization.nix (ADR-0020).
# Usage: contract-greeter-provision <username> <identity.json> <activation-package> <tier> <mode>
# NixOS users are declarative, and a greeter user is never built into the system (ADR-0018), so
# realization.nix never runs for them — this IS their realization, run at login. It materializes
# the (Tier-1 persisted) account and FULLY realizes it from identity.json + the SELECTED MODE:
# password (the same hash auth verified ⇒ PAM works), authorizedKeys, GECOS, and the groups its
# session shape needs, plus the greeter-seat baseline. Then it activates the built home AS the user.
# Tier-2 (ephemeral) is deferred. Runs as root (greetd's pre-session context); it drops to the user
# for activation. The activated session is secret-free: the contract handles no secrets beyond the
# login credential.
#
# It is the RUNTIME ADAPTER over accountPlan (ADR-0020), the twin of realization.nix's build-time
# adapter — and, since issue #31's follow-up, a PURE RENDERER: it owns NO account-combining logic.
# The four-field rule (clamp ∪ grant, drop-empty-sshKey, GECOS, password) lives in ONE place —
# `accountPlan` — which this script EVALUATES via the `contract-account-plan` tool (which re-imports
# the contract and runs the same pure function build-time realization uses). This replaces the jq
# re-spelling that issue #31 had to keep in step by booting a VM; there is now a single source, so
# the greeter-provision VM proves this renderer SURFACES the record faithfully, not that two
# spellings agree, and the rule's own guarantees (the clamp, the empty-sshKey drop) are proven
# without a boot in conformance/account-plan.nix. What remains here is strictly RENDER: run the
# evaluator, then write GECOS, the password, authorizedKeys, and the groups (the record's groups ∪
# the greeter-seat groups — the baseline plus the `greeter-users` seat MARKER, which is seat
# infrastructure layered on top of the portable account, not part of it, ADR-0018).
{
  pkgs,
  accountPlanEval,
  # What a greeter seat affords (the safe set) and the seat's enrolled groups, both frozen to store
  # JSON by greeter.nix. `provision` hands the grant to the evaluator and unions the seat groups
  # (baseline ∪ the `greeter-users` marker) into the record's groups before enrolling.
  greeterGrantsFile,
  seatGroupsFile,
}:
pkgs.writeShellApplication {
  name = "contract-greeter-provision";
  runtimeInputs = [
    pkgs.jq
    pkgs.shadow
    pkgs.coreutils
    pkgs.util-linux
    accountPlanEval
  ];
  text = ''
    # ARITY IS THE INTERFACE: five positional args, in a fixed order. Check it explicitly so a
    # drifted caller gets a NAMED error naming the usage line, rather than the bare
    # `$5: unbound variable` that `set -u` raises three lines down — the failure mode that let a
    # four-argument caller reach a booted VM before anyone learned which argument was missing.
    [ "$#" -eq 5 ] || {
      echo "provision: expected 5 arguments, got $#" >&2
      echo "usage: contract-greeter-provision <username> <identity.json> <activation-package> <tier> <mode>" >&2
      exit 1
    }

    username=$1
    identity=$2
    activation=$3
    tier=$4
    mode=$5

    [ "$(id -u)" = 0 ] || { echo "provision: must run as root" >&2; exit 1; }
    [ -f "$identity" ] || { echo "provision: no identity.json at '$identity'" >&2; exit 1; }
    [ -x "$activation/activate" ] || { echo "provision: '$activation' is not a home-activation package" >&2; exit 1; }

    case "$tier" in
      tier1) : ;; # persisted (a normal account with a real home, ADR-0018)
      tier2) echo "provision: tier2 (ephemeral) provisioning is deferred (ADR-0018)" >&2; exit 1 ;;
      *) echo "provision: unknown tier '$tier'" >&2; exit 1 ;;
    esac

    home="/home/$username"
    if ! id -u "$username" >/dev/null 2>&1; then
      useradd --create-home --home-dir "$home" --shell /run/current-system/sw/bin/bash \
        --user-group "$username"
    fi

    # --- runtime adapter over accountPlan (ADR-0020): evaluate, then render ---
    # Compute the account record from the ONE shared accountPlan (identity + the safe-set grant),
    # via the contract's own evaluator — no combining logic is reproduced here. Fail-CLOSED: if the
    # evaluation fails (a malformed identity that slipped past auth, a contract bug), abort before
    # touching the account rather than realize a half-account.
    if ! record=$(contract-account-plan "$identity" ${greeterGrantsFile} "$mode"); then
      echo "provision: account-plan evaluation failed for '$username'" >&2
      exit 1
    fi

    # GECOS = the record's description.
    name=$(jq -r '.description // empty' <<<"$record")
    [ -n "$name" ] && usermod -c "$name" "$username"

    # Password = the record's hashedPassword (the same value auth verified) ⇒ PAM works.
    hash=$(jq -r '.hashedPassword // empty' <<<"$record")
    [ -n "$hash" ] && printf '%s:%s\n' "$username" "$hash" | chpasswd -e

    # Groups = the record's (mode ∪ granted) groups ∪ the greeter-seat groups (the baseline plus
    # the `greeter-users` marker), restricted to groups that exist on the seat (the baseline is
    # pre-realized declaratively; a stray name is skipped, not created). The clamp already happened
    # inside accountPlan — a privileged group declared in identity.json is absent from the record.
    readarray -t want < <(jq -r '.extraGroups[]?' <<<"$record")
    readarray -t seat < <(jq -r '.[]?' ${seatGroupsFile})
    add=()
    for g in "''${want[@]}" "''${seat[@]}"; do
      getent group "$g" >/dev/null 2>&1 && add+=("$g")
    done
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
