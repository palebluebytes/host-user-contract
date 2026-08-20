# The orchestrator greetd runs: ties the eval-free ordering together (the replaceable UI half).
# The prompt loop here is the reference UI; a host may swap regreet/its own front end as long as it
# preserves the ordering. The home BUILD (step 5/6) is delegated to the host's `homeBuilder`
# binding — it needs home-manager, which the contract does not ship. The session it activates is
# always secret-free: the contract handles no secrets beyond the login credential.
{
  pkgs,
  lib,
  identityFile,
  tier,
  trustedSigners,
  homeBuilder,
  tier1NixConfig,
  authScript,
  provisionScript,
  sessionScript,
  # The mode-selection evaluator: the contract's OWN `selectModeOver`, executed at login. The seat's
  # run set and the floor are read from the contract inside it, so nothing about what this machine
  # can run is stated here — see ./mode-select-eval.nix.
  modeSelectScript,
  # The seat's own system, so the user's flake can be looked up under the right key.
  system,
}:
pkgs.writeShellApplication {
  name = "contract-greeter-bind";
  runtimeInputs = [
    pkgs.nix
    pkgs.jq
    pkgs.coreutils
    authScript
    provisionScript
    sessionScript
    modeSelectScript
  ];
  text = ''
    tier=${lib.escapeShellArg tier}
    signers=${
      if trustedSigners == [ ] then
        "/var/empty/contract-greeter-signers"
      else
        pkgs.writeText "contract-greeter-allowed-signers" (
          lib.concatMapStringsSep "\n" (k: "* ${k}") trustedSigners
        )
    }
    homeBuilder=${lib.escapeShellArg (toString homeBuilder)}
    system=${lib.escapeShellArg system}

    # The restricted-eval posture the home is built under, DISPATCHED BY TIER: a host-signed repo
    # is still built under a restricted eval it cannot widen. Selected by tier so the posture is
    # honestly tier-scoped — tier1 uses the contract's canonical, conformance-checked
    # tier1EvalConfig; tier2 (untrusted, ephemeral) is DEFERRED and refused here, before any build,
    # rather than silently building under tier1's floor. accept-flake-config=false is applied to
    # the fetch too (below), so the repo's own nixConfig is ignored even while locking.
    case "$tier" in
      tier1) evalConfig=${lib.escapeShellArg tier1NixConfig} ;;
      *) echo "greeter: no eval posture defined for tier '$tier' (tier2 deferred)" >&2; exit 1 ;;
    esac

    [ -n "$homeBuilder" ] || {
      echo "greeter: no homeBuilder bound — a seat host must set contract.greeter.homeBuilder" >&2
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

    # 4b. SELECT THE MODE — the same selection a declarative bind makes, because it is literally the
    # same code: `contract-select-mode` evaluates the contract's own `selectModeOver` kernel, with
    # the seat's run set and the floor read from the contract inside it. Nothing about selection is
    # spelled in this script, which is the point — a shell transcription of the rule had already
    # drifted from the Nix one on the two-incomparable-modes case.
    #
    # What the USER's flake is asked for is just a list of mode names, and it is asked under the
    # SAME restricted-eval posture as the build below: this is the first moment any of the user's
    # Nix runs, so it is not permitted to be freer than step 5/6.
    #
    # Two probes, most authoritative first:
    #   1. the binding INDEX (`contractUsers.<sys>.<user>.modes`) — plain data, forces no home;
    #   2. the published HOMES themselves — the very set the homeBuilder is about to reach into, so
    #      a users repo that publishes homes without an index still selects correctly rather than
    #      falling back and then failing the build at a login prompt.
    # Neither readable ⇒ no published set, and the evaluator answers with the floor, which every
    # host runs. A seat whose homeBuilder builds something else entirely lands here, which is why
    # it is a warning rather than a refusal.
    published=""
    if published=$(env NIX_CONFIG="$evalConfig" nix eval --json \
        "$src#contractUsers.$system.$username.modes" 2>/dev/null); then
      :
    elif published=$(env NIX_CONFIG="$evalConfig" nix eval --json \
        "$src#homes.$system.$username" --apply builtins.attrNames 2>/dev/null); then
      :
    else
      echo "greeter: $flake publishes neither a binding index nor homes for '$username' on $system" >&2
      echo "         — selecting the floor, which every host runs" >&2
      published=""
    fi

    pubfile=""
    if [ -n "$published" ]; then
      pubfile=$(mktemp)
      printf '%s' "$published" > "$pubfile"
    fi
    # A refusal here is the contract's own named diagnostic, thrown by the kernel itself.
    mode=$(contract-select-mode "$username" "$pubfile")
    if [ -n "$pubfile" ]; then rm -f "$pubfile"; fi
    echo "greeter: binding '$username' in mode '$mode'" >&2

    # 5/6. evaluate + build the home THROUGH the contract, under the contract-pinned restricted-eval
    # posture — handed to the host's homeBuilder as NIX_CONFIG so a naive `nix build` binding
    # inherits the floor; it augments the seat's nix.conf (experimental-features survive).
    activation=$(env NIX_CONFIG="$evalConfig" "$homeBuilder" "$src" "$username" "$mode")

    # 7. FULLY realize the account (shell-side realization.nix) and activate the (secret-free) home.
    # The MODE goes with it: a graphical session's input groups ride the mode, so the account plan
    # needs to know which session shape this login was bound in.
    contract-greeter-provision "$username" "$src/${identityFile}" "$activation" "$tier" "$mode"

    # 8. launch the session (the desktop is selected here; the host-bound backend renders it).
    exec contract-greeter-session "$username" "/home/$username"
  '';
}
