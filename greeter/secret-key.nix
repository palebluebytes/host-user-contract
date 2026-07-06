# (4b) the secret key acquisition step (ADR-0015, issues #10/#11): from the seat's baked config,
# obtain the user's session age key — from their repo (passphrase method) or via the host's
# keyFetcher binding (escrow method) — decrypt it with contract-greeter-unlock, and emit the
# temp-file path on stdout. Three outcomes:
#   - key obtained: emits the path, exits 0. Caller cleans up the file after provision places it.
#   - graceful degradation: emits nothing, exits 0 (no key available + requireSecrets=false).
#   - refused: exits non-zero (exposed host, or requireSecrets=true with no key obtainable).
#
# All seat config is baked at module-eval time (method, wrappedKeyName, keyFetcher,
# requireSecrets, separatePassphrase, tier, exposed). Runtime args are username and src.
#
# When separatePassphrase=false, the login password is expected in the CONTRACT_LOGIN_PASS
# environment variable (set by the bind orchestrator, which already holds it). When
# separatePassphrase=true, this script prompts on the TTY directly (stdin is still the terminal
# inside bind's command substitution).
{
  pkgs,
  lib,
  unlockScript,
  secretProvisioning,
  tier,
  exposed,
}:
pkgs.writeShellApplication {
  name = "contract-greeter-secret-key";
  runtimeInputs = [
    pkgs.coreutils
    unlockScript
  ];
  text = ''
    # Baked seat config (resolved at module-eval time, ADR-0015)
    secretProv=${lib.boolToString secretProvisioning.enable}
    method=${lib.escapeShellArg secretProvisioning.method}
    keyFetcher=${lib.escapeShellArg (toString secretProvisioning.keyFetcher)}
    requireSecrets=${lib.boolToString secretProvisioning.requireSecrets}
    separatePass=${lib.boolToString secretProvisioning.separatePassphrase}
    wrappedName=${lib.escapeShellArg secretProvisioning.wrappedKeyName}
    tier=${lib.escapeShellArg tier}
    exposed=${lib.boolToString exposed}

    username=$1
    src=$2

    # Not enabled or not tier1: graceful no-op (tier2 is secret-free by design, ADR-0015)
    if [ "$secretProv" = false ] || [ "$tier" != tier1 ]; then
      exit 0
    fi

    # Exposed host: the seat sees the user's plaintext during activation — indefensible (ADR-0001)
    if [ "$exposed" = true ]; then
      echo "secret-key: secret provisioning refused on an exposed host (ADR-0001)" >&2; exit 1
    fi

    # Key acquisition: where the wrapped key comes from (ADR-0015, issues #10/#11). Both paths
    # yield a wrapped-key FILE the same passphrase-unlock + placement path consumes. The escrow
    # fetch streams to a file (binary-safe: a wrapped key is openssl ciphertext, not ASCII; a
    # shell var would drop NUL bytes).
    wrappedKey=""
    cleanupWrapped=""
    case "$method" in
      passphrase)
        [ -f "$src/$wrappedName" ] && wrappedKey="$src/$wrappedName"
        ;;
      escrow)
        if [ -z "$keyFetcher" ]; then
          echo "secret-key: escrow needs a keyFetcher binding; none set" >&2
        else
          wrappedKey=$(mktemp); cleanupWrapped=$wrappedKey
          "$keyFetcher" "$username" > "$wrappedKey" \
            || { echo "secret-key: escrow keyFetcher failed (server unreachable / no approval)" >&2
                 rm -f "$wrappedKey"; wrappedKey=""; }
        fi
        ;;
    esac

    sessionKey=""
    if [ -n "$wrappedKey" ] && [ -s "$wrappedKey" ]; then
      # Unlock passphrase: separate prompt (recommended) or reuse the login password (ADR-0015).
      # separatePassphrase=false: bind already holds the password; it passes it as CONTRACT_LOGIN_PASS.
      if [ "$separatePass" = true ]; then
        printf 'unlock passphrase: ' >&2
        stty -echo 2>/dev/null || true
        read -r unlockpass
        stty echo 2>/dev/null || true
        printf '\n' >&2
      else
        unlockpass=''${CONTRACT_LOGIN_PASS:-}
      fi
      sessionKey=$(mktemp)
      chmod 600 "$sessionKey"
      printf '%s\n' "$unlockpass" | contract-greeter-unlock "$wrappedKey" > "$sessionKey" \
        || { echo "secret-key: unlock failed (wrong passphrase or corrupt wrapped key)" >&2
             rm -f "$sessionKey"; sessionKey=""; }
    fi
    [ -n "$cleanupWrapped" ] && rm -f "$cleanupWrapped"

    # Fail CLOSED on secrets, never on the login (ADR-0015): degrade to a secret-free session
    # unless requireSecrets demands otherwise. No in-repo passphrase fallback for escrow — that
    # would be a downgrade attack.
    if [ -z "$sessionKey" ]; then
      if [ "$requireSecrets" = true ]; then
        echo "secret-key: requireSecrets is set but no key could be obtained ($method) — refusing the login" >&2
        exit 1
      fi
      echo "secret-key: could not obtain a key ($method); continuing secret-free" >&2
      exit 0
    fi

    printf '%s' "$sessionKey"
  '';
}
