# The orchestrator greetd runs: ties the eval-free ordering together (the replaceable UI half).
# The prompt loop here is the reference UI; a host may swap regreet/its own front end as long as it
# preserves the ordering. The home BUILD (step 5/6) is delegated to the host's `homeBuilder` binding —
# it needs home-manager, which the contract does not ship (ADR-0020).
{
  pkgs,
  lib,
  identityFile,
  tier,
  trustedSigners,
  homeBuilder,
  tier1NixConfig,
  exposed,
  secretProvisioning,
  authScript,
  provisionScript,
  sessionScript,
  unlockScript,
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
    unlockScript
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

    # Secret-provisioning settings (ADR-0031, issue #10), baked from the seat's binding.
    secretProv=${lib.boolToString secretProvisioning.enable}
    separatePass=${lib.boolToString secretProvisioning.separatePassphrase}
    keyRel=${lib.escapeShellArg secretProvisioning.keyFile}
    wrappedName=${lib.escapeShellArg secretProvisioning.wrappedKeyName}
    exposed=${lib.boolToString exposed}

    # The restricted-eval posture the home is built under, DISPATCHED BY TIER (ADR-0030): a
    # host-signed repo is still built under a restricted eval it cannot widen. Selected by tier so
    # the posture is honestly tier-scoped — tier1 uses the contract's canonical, conformance-checked
    # tier1EvalConfig; tier2 (untrusted, ephemeral) is DEFERRED and refused here, before any build,
    # rather than silently building under tier1's floor. accept-flake-config=false is applied to the
    # fetch too (below), so the repo's own nixConfig is ignored even while locking.
    case "$tier" in
      tier1) evalConfig=${lib.escapeShellArg tier1NixConfig} ;;
      *) echo "greeter: no eval posture defined for tier '$tier' (tier2 deferred, ADR-0030)" >&2; exit 1 ;;
    esac

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

    # 4b. SECRET PROVISIONING (ADR-0031, issue #10): on a TRUSTED Tier-1 seat, turn the user's
    # passphrase into their KEY so their OWN home sops decrypt at this roaming login. REFUSED on an
    # exposed host (ADR-0015 — the seat sees the plaintext) and skipped at tier2 (secret-free). The
    # decrypted identity goes to a private temp file passed to provision; it never hits argv.
    sessionKey=""
    if [ "$secretProv" = true ] && [ "$tier" = tier1 ]; then
      if [ "$exposed" = true ]; then
        echo "greeter: secret provisioning refused on an exposed host (ADR-0015)" >&2; exit 1
      fi
      if [ -f "$src/$wrappedName" ]; then
        if [ "$separatePass" = true ]; then
          printf 'unlock passphrase: ' >&2; stty -echo 2>/dev/null || true; read -r unlockpass; stty echo 2>/dev/null || true; printf '\n' >&2
        else
          unlockpass=$password
        fi
        sessionKey=$(mktemp)
        chmod 600 "$sessionKey"
        printf '%s\n' "$unlockpass" | contract-greeter-unlock "$src/$wrappedName" > "$sessionKey"
      else
        echo "greeter: secret provisioning enabled but no wrapped key ($wrappedName) in repo; continuing secret-free" >&2
      fi
    fi

    # 5/6. evaluate + build the home THROUGH the contract, under the contract-pinned restricted-eval
    # posture (ADR-0030) — handed to the host's homeBuilder as NIX_CONFIG so a naive `nix build`
    # binding inherits the floor; it augments the seat's nix.conf (experimental-features survive).
    activation=$(env NIX_CONFIG="$evalConfig" "$homeBuilder" "$src" "$username")

    # 7. FULLY realize the account (shell-side realization.nix), place the unlocked key, activate.
    contract-greeter-provision "$username" "$src/${identityFile}" "$activation" "$tier" "$sessionKey" "$keyRel"
    [ -n "$sessionKey" ] && rm -f "$sessionKey"

    # 8. launch the session (the desktop is selected here; the host-bound backend renders it).
    exec contract-greeter-session "$username" "/home/$username"
  '';
}
