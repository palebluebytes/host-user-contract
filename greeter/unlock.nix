# (4b) the secret-unlock step (ADR-0031, issue #10): turn the user's PASSPHRASE into their KEY.
# Usage: contract-greeter-unlock <wrapped-key-file>   (unlock passphrase on stdin)
#
# A roaming user's OWN home secrets (their sops) decrypt with the user's private key, which a greeter
# does not have — it holds a password. So the user's repo carries their age identity wrapped with a
# passphrase; this decrypts it to stdout, and the greeter places it for home activation so the user's
# sops decrypt at the login. It runs ONLY on a trusted, non-exposed Tier-1 seat (gated in bind, never
# here), and never logs the passphrase or the key.
#
# Wrapping convention (the user runs the inverse): a magic header line + the age identity, encrypted
# AES-256-CBC + PBKDF2 (the cipher is unauthenticated, so the header makes a wrong passphrase a CLEAN
# failure, not a silently-garbage key):
#   printf 'contract-age-key-v1\n%s' "$(cat age-identity.txt)" \
#     | openssl enc -e -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass stdin -out contract-key.enc
{ pkgs }:
let
  magic = "contract-age-key-v1";
  iter = "600000";
in
pkgs.writeShellApplication {
  name = "contract-greeter-unlock";
  runtimeInputs = [
    pkgs.openssl
    pkgs.coreutils
  ];
  text = ''
    wrapped=$1
    [ -f "$wrapped" ] || { echo "unlock: no wrapped key at '$wrapped'" >&2; exit 1; }

    # Unlock passphrase on stdin; ciphertext from the file. A wrong passphrase fails decryption (PBKDF2
    # + CBC padding) OR survives to a header mismatch — either way a clean refusal, never a bad key.
    plain=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter ${iter} -pass stdin -in "$wrapped" 2>/dev/null) \
      || { echo "unlock: wrong passphrase or corrupt wrapped key" >&2; exit 1; }
    [ "$(printf '%s\n' "$plain" | head -n1)" = "${magic}" ] \
      || { echo "unlock: wrong passphrase (header mismatch)" >&2; exit 1; }

    # Emit the age identity — everything after the magic header line.
    printf '%s\n' "$plain" | tail -n +2
  '';
}
