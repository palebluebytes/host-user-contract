# Gate test for the reference escrow keyserver (issue #13, ADR-0031). Proves the REAL composition —
# release-server.py + the reference key-fetcher — enforces the release gate end-to-end, with a
# keypair-controlled "phone" standing in for the real device (no phone/WebAuthn dependency). It tests
# the value-adds over the contract's minimal seam fixture: NUMBER-MATCHING, a ONE-TIME requester-bound
# token, BINARY-safe transport, and signature verification.
{ pkgs }:
pkgs.runCommand "escrow-keyserver-gate"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.openssl
      pkgs.curl
      pkgs.jq
      pkgs.coreutils
      pkgs.bash
    ];
  }
  ''
    export HOME=$PWD

    # The "phone": an ed25519 keypair the server trusts; an attacker key stands for an unauthorized device.
    openssl genpkey -algorithm ed25519 -out phone.key 2>/dev/null
    openssl pkey -in phone.key -pubout -out phone.pub 2>/dev/null
    openssl genpkey -algorithm ed25519 -out attacker.key 2>/dev/null

    # alice's wrapped key — BINARY (NUL + high bytes), as a real openssl-wrapped key is. The store holds
    # it base64-encoded (one line per user); the server decodes + serves the raw bytes.
    printf 'wrapped\x00age\x00key\xff\xfe\x01bytes' > alice.wrapped
    printf 'alice:%s\n' "$(base64 -w0 alice.wrapped)" > store.txt

    port=8731
    url="http://127.0.0.1:$port"
    export NTFY_CAPTURE=$PWD/push.json   # stands in for the phone's inbox

    python3 ${./release-server.py} "$port" phone.pub store.txt &
    server=$!
    trap 'kill $server 2>/dev/null || true' EXIT
    for _ in $(seq 1 50); do curl -s -o /dev/null "$url/key/ping" && break; sleep 0.1; done

    # The phone: read the pushed prompt, sign the server's challenge for <token>, POST the approval with
    # the match <number> + signature, using private key $3.
    approve() { # <token> <number> <privkey>
      curl -fsS "$url/challenge/$1" | base64 -d > chal
      openssl pkeyutl -sign -inkey "$3" -rawin -in chal -out sig 2>/dev/null
      printf '{"number":"%s","signature":"%s"}' "$2" "$(base64 -w0 sig)" \
        | curl -fsS -X POST --data-binary @- "$url/approve/$1"
    }
    fresh() { curl -fsS -X POST "$url/request/alice"; } # a fresh request → JSON {token, number, challenge}

    echo "# POSITIVE: the reference key-fetcher requests; a valid number-matched approval releases the key BYTE-EXACT"
    export CONTRACT_KEYFETCHER_URL="$url"
    CONTRACT_KEYFETCHER_POLL=30 bash ${./key-fetcher} alice > got.key 2>fetch.err &
    fetch=$!
    for _ in $(seq 1 50); do [ -s push.json ] && break; sleep 0.1; done   # wait for the fetcher's request → push
    token=$(jq -r .token push.json); number=$(jq -r .number push.json)
    approve "$token" "$number" phone.key >/dev/null
    wait "$fetch" || { echo "FAIL: key-fetcher did not return after a valid approval" >&2; cat fetch.err >&2; exit 1; }
    cmp -s alice.wrapped got.key || { echo "FAIL: released key corrupted/mismatched (binary-unsafe?)" >&2; exit 1; }

    echo "# NEGATIVE: a WRONG match number is rejected — no release (number-matching)"
    r=$(fresh); t=$(printf '%s' "$r" | jq -r .token); n=$(printf '%s' "$r" | jq -r .number)
    wrong=$(printf '%02d' $(( (10#$n + 1) % 100 )))
    if approve "$t" "$wrong" phone.key 2>/dev/null | grep -q approved; then echo "FAIL: wrong number accepted" >&2; exit 1; fi
    if curl -fsS "$url/key/$t" >/dev/null 2>&1; then echo "FAIL: released despite a wrong number" >&2; exit 1; fi

    echo "# NEGATIVE: an ATTACKER signature is rejected — no release"
    r=$(fresh); t=$(printf '%s' "$r" | jq -r .token); n=$(printf '%s' "$r" | jq -r .number)
    if approve "$t" "$n" attacker.key 2>/dev/null | grep -q approved; then echo "FAIL: attacker signature accepted" >&2; exit 1; fi
    if curl -fsS "$url/key/$t" >/dev/null 2>&1; then echo "FAIL: released despite a bad signature" >&2; exit 1; fi

    echo "# ONE-TIME: a released token yields the key exactly once, then is destroyed"
    r=$(fresh); t=$(printf '%s' "$r" | jq -r .token); n=$(printf '%s' "$r" | jq -r .number)
    approve "$t" "$n" phone.key >/dev/null
    curl -fsS -o once.key "$url/key/$t" || { echo "FAIL: first collection failed" >&2; exit 1; }
    cmp -s alice.wrapped once.key || { echo "FAIL: one-time key mismatch" >&2; exit 1; }
    if curl -fsS "$url/key/$t" >/dev/null 2>&1; then echo "FAIL: one-time token was reusable" >&2; exit 1; fi

    echo "escrow keyserver gate OK"; touch $out
  ''
