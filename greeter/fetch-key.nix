# (4a-escrow) the phone-gated escrow fetch (ADR-0031, issue #11): a different SOURCE for the same
# "obtain the user's key" seam — instead of a passphrase-wrapped key in the repo (issue #10), the
# wrapped key lives on the user's OWN trusted server and is released only after a PHONE approval.
# Usage: contract-greeter-fetch-key <release-url> <username>   (the released wrapped key to stdout)
#
# The seat only REQUESTS and POLLS. The phone↔server approval — a WebAuthn/passkey assertion or a
# tapped push that authorizes the release — is the user's SERVER's concern (a host binding, like
# homeBuilder), never the seat's: the seat never holds the phone's key, it just waits for the server
# to release. That removes the offline-brute-force target (the wrapped key is no longer public) while
# the fetched key still feeds the same unlock+placement path as the passphrase method.
{ pkgs }:
pkgs.writeShellApplication {
  name = "contract-greeter-fetch-key";
  runtimeInputs = [
    pkgs.curl
    pkgs.coreutils
  ];
  text = ''
    url=''${1%/}
    username=$2
    # Seconds to wait for the phone approval (overridable for tests; the default suits a person tapping).
    poll=''${CONTRACT_FETCH_KEY_POLL:-60}

    # Ask the user's server to release the key — it pushes an approval to the user's phone.
    curl -fsS -X POST "$url/request/$username" >/dev/null \
      || { echo "fetch-key: release request to '$url' failed" >&2; exit 1; }

    # Poll for the release; the server returns the wrapped key only AFTER the phone approves.
    for _ in $(seq 1 "$poll"); do
      if body=$(curl -fsS "$url/key/$username" 2>/dev/null); then
        printf '%s' "$body"
        exit 0
      fi
      sleep 1
    done
    echo "fetch-key: timed out waiting for phone approval (no release from '$url')" >&2
    exit 1
  '';
}
