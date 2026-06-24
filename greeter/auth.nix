# (3) the eval-free auth: jq over the inert identity.json, zero lines of user Nix.
# Usage: contract-greeter-auth <src> <username> <tier> <allowed-signers-file>  (password on stdin)
# The CANONICAL, mandatory mechanism (ADR-0024 condition 1). It reads only data (`jq`) and
# re-hashes the password with libc crypt (via perl, which covers yescrypt/sha512crypt exactly
# as /etc/shadow does) — it never evaluates the user's flake.
{ pkgs, identityFile }:
pkgs.writeShellApplication {
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
}
