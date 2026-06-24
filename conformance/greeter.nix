# Conformance domain: the reference greeter module (ADR-0024, issue #2) and the Tier-1 restricted-eval
# posture it applies (ADR-0030). Eval-level claims (the present-but-unbound litmus, the FIXED safe-set
# grant, the pinned eval posture) plus two EXECUTION proofs built as sub-derivations: the eval-free
# auth flow and the restricted-eval enforcement. Returns those drvs so ./default.nix builds them.
{
  lib,
  pkgs,
  toolkit,
  greeterModule,
  greeterGrants,
  safeSet,
  tier1EvalConfig,
  renderNixConfig,
}:
let
  inherit (toolkit) eval;

  # The opt-in greetd + eval-free-bind + provision module. Present-but-UNBOUND must turn nothing on;
  # ENABLED it wires greetd to the contract bind command with the grant FIXED to the safe set.
  greeterUnbound = eval [ greeterModule ];
  greeterBound = eval [
    greeterModule
    {
      custom.greeter.enable = true;
      custom.greeter.homeBuilder = "/run/current-system/sw/bin/true";
    }
  ];

  # The auth-flow EXECUTION test (ADR-0024 condition 1, the CANONICAL eval-free auth): pull the
  # actual shipped `contract-greeter-auth` script out of the enabled greeter's systemPackages and
  # run it against the example user repo's identity.json. It must accept the right password and
  # reject a wrong one / a mismatched username — having read only data (`jq` + libc crypt), never
  # the user's Nix. Tier 2 isolates the password check (no signature); the Tier-1 block then
  # exercises the signature branch with a real SSH key (good signature accepts, untrusted-key and
  # absent signatures reject). The cleartext for the example's hashedPassword is
  # "correct-horse-battery-staple".
  authScript =
    lib.findFirst (p: lib.hasInfix "contract-greeter-auth" (p.name or ""))
      (throw "conformance: contract-greeter-auth not found in the greeter's systemPackages")
      greeterBound.environment.systemPackages;
  exampleSrc = ../examples/user;
  authFlowTest =
    pkgs.runCommand "contract-greeter-auth-flow"
      {
        nativeBuildInputs = [
          authScript
          pkgs.openssh
        ];
      }
      ''
        export HOME=$PWD
        src=${exampleSrc}

        echo "# right password ⇒ accepts"
        printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth "$src" example tier2 /dev/null

        echo "# wrong password ⇒ rejects"
        if printf '%s\n' 'wrong-password' \
          | contract-greeter-auth "$src" example tier2 /dev/null 2>/dev/null; then
          echo "FAIL: a wrong password was accepted" >&2; exit 1
        fi

        echo "# username mismatch ⇒ rejects (no impersonation)"
        if printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth "$src" someone-else tier2 /dev/null 2>/dev/null; then
          echo "FAIL: a mismatched username was accepted" >&2; exit 1
        fi

        # --- Tier 1: the repo must be SIGNED by a host-trusted key (ADR-0022) ---
        # Build a signed source: the example identity.json + an SSH signature over the tree
        # manifest (exactly what the auth script recomputes and verifies), plus the allowed-signers
        # file a host would derive from custom.greeter.trustedSigners.
        ssh-keygen -q -t ed25519 -N "" -C trusted -f trusted
        ssh-keygen -q -t ed25519 -N "" -C attacker -f attacker
        mkdir signed
        cp "$src/identity.json" signed/identity.json
        manifest=$(cd signed && find . -type f ! -name contract.sig -print0 | sort -z | xargs -0 sha256sum)
        printf '%s' "$manifest" > manifest.txt
        ssh-keygen -Y sign -f trusted -n contract manifest.txt
        cp manifest.txt.sig signed/contract.sig
        printf '* %s\n' "$(cat trusted.pub)" > trusted-signers
        printf '* %s\n' "$(cat attacker.pub)" > attacker-signers

        echo "# tier1: a host-trusted signature over the repo ⇒ accepts"
        printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth signed example tier1 trusted-signers

        echo "# tier1: a signature by an UNTRUSTED key ⇒ rejects"
        if printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth signed example tier1 attacker-signers 2>/dev/null; then
          echo "FAIL: a signature by an untrusted key was accepted" >&2; exit 1
        fi

        echo "# tier1: no signature at all ⇒ rejects"
        if printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth "$src" example tier1 trusted-signers 2>/dev/null; then
          echo "FAIL: an unsigned repo was accepted at tier1" >&2; exit 1
        fi

        echo "eval-free auth flow OK" ; touch $out
      '';

  # The restricted-eval EXECUTION test (ADR-0030): prove the contract's PINNED Tier-1 posture, when
  # rendered to NIX_CONFIG exactly as the greeter hands it to the homeBuilder, actually RESTRICTS a
  # real Nix eval — not just that the attrset spells the right words. We run the very renderer the
  # greeter uses (renderNixConfig tier1EvalConfig) into NIX_CONFIG, then evaluate a hostile
  # expression that reads a host file. Under the posture restrict-eval=true MUST block it; without
  # the posture the same eval succeeds (the control), proving the posture is what restricts.
  tier1NixConfigFile = builtins.toFile "tier1-nix.conf" (renderNixConfig tier1EvalConfig);
  restrictedEvalTest =
    pkgs.runCommand "contract-tier1-restricted-eval"
      {
        nativeBuildInputs = [ pkgs.nix ];
      }
      ''
        export HOME=$PWD NIX_STATE_DIR=$PWD/nix/var NIX_STORE_DIR=/nix/store

        # A host file OUTSIDE the store the hostile expression tries to read by absolute path.
        secret=$PWD/host-secret
        echo "a host file no user repo should reach" > "$secret"
        expr="builtins.readFile \"$secret\""

        echo "# control: a hostile readFile evaluates WITHOUT the posture"
        nix-instantiate --eval --expr "$expr" >/dev/null \
          || { echo "FAIL: the control eval did not even run" >&2; exit 1; }

        echo "# the contract's pinned posture (via NIX_CONFIG) BLOCKS the same hostile readFile"
        export NIX_CONFIG=$(cat ${tier1NixConfigFile})
        if nix-instantiate --eval --expr "$expr" >/dev/null 2>err; then
          echo "FAIL: restrict-eval did NOT block a host-file read under the pinned posture" >&2
          exit 1
        fi
        grep -q "access to absolute path" err || grep -qi "restricted" err \
          || { echo "FAIL: blocked, but not by the restricted-eval policy:" >&2; cat err >&2; exit 1; }

        echo "tier1 restricted-eval posture OK (restrict-eval enforced via NIX_CONFIG)"
        touch $out
      '';

  # Secret provisioning (ADR-0031, issue #10): enabling it on an EXPOSED host must fail an assertion —
  # the seat sees the user's plaintext while activating the home, indefensible on an agent box (ADR-0015).
  greeterSecretExposed = eval [
    greeterModule
    {
      custom.greeter.enable = true;
      custom.greeter.homeBuilder = "/run/current-system/sw/bin/true";
      custom.greeter.secretProvisioning.enable = true;
      custom.host.exposed = true;
      networking.hostName = "agent";
    }
  ];

  # The unlock EXECUTION test (ADR-0031): pull the shipped `contract-greeter-unlock` and prove it turns
  # the user's PASSPHRASE into their KEY — wrap a real age identity with the contract's convention (magic
  # header + openssl pbkdf2), then the right passphrase recovers exactly that identity, a wrong one is
  # cleanly rejected, and the magic header never leaks into the placed key.
  unlockScript =
    lib.findFirst (p: lib.hasInfix "contract-greeter-unlock" (p.name or ""))
      (throw "conformance: contract-greeter-unlock not found in the greeter's systemPackages")
      greeterBound.environment.systemPackages;
  unlockFlowTest =
    pkgs.runCommand "contract-greeter-unlock-flow"
      {
        nativeBuildInputs = [
          unlockScript
          pkgs.openssl
          pkgs.age
        ];
      }
      ''
        export HOME=$PWD

        # A user age identity, wrapped with the contract convention (magic header line + the age key,
        # encrypted AES-256-CBC + PBKDF2 — exactly what the user runs).
        age-keygen -o id.txt 2>/dev/null
        { printf 'contract-age-key-v1\n'; cat id.txt; } > plain.txt
        printf 'unlock-pass' \
          | openssl enc -e -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass stdin -in plain.txt -out contract-key.enc

        echo "# right passphrase ⇒ recovers the user's age identity, header stripped"
        printf 'unlock-pass' | contract-greeter-unlock contract-key.enc > out.txt
        grep -qF "$(grep '^AGE-SECRET-KEY' id.txt)" out.txt || { echo "FAIL: did not recover the identity" >&2; exit 1; }
        grep -q 'contract-age-key-v1' out.txt && { echo "FAIL: magic header leaked into the key" >&2; exit 1; }

        echo "# wrong passphrase ⇒ rejects (no garbage key)"
        if printf 'WRONG-pass' | contract-greeter-unlock contract-key.enc >/dev/null 2>&1; then
          echo "FAIL: a wrong passphrase was accepted" >&2; exit 1
        fi

        echo "unlock flow OK"; touch $out
      '';
in
{
  drvs = {
    greeterAuthFlow = authFlowTest;
    tier1RestrictedEval = restrictedEvalTest;
    greeterUnlockFlow = unlockFlowTest;
  };

  assertions = [
    {
      # The greeter grant (ADR-0022/0024): default-open over the safe set — it enables exactly
      # the runtime-eligible features, no operator choice, no more.
      name = "greeterGrants: enables exactly the safe set (default-open, nothing beyond it)";
      ok =
        (lib.sort (a: b: a < b) (lib.attrNames greeterGrants) == lib.sort (a: b: a < b) safeSet)
        && lib.all (n: greeterGrants.${n}.enable) (lib.attrNames greeterGrants);
    }
    {
      # ADR-0024 conformance condition (3): a greeter grants AT MOST the safe set, so a
      # runtime-bound user can never receive a privileged-group or secret-bearing feature —
      # escalation is impossible by construction, not by a deny rule.
      name = "greeterGrants: grants no privileged-group or secret-bearing feature (no escalation)";
      ok =
        !(lib.elem "workstation" (lib.attrNames greeterGrants))
        && !(lib.elem "virtualization" (lib.attrNames greeterGrants))
        && !(lib.elem "signing" (lib.attrNames greeterGrants));
    }
    {
      # ADR-0024 litmus (mirrors the platform interface): the greeter ships in the eval but a
      # host that does not enable it gets nothing — greetd stays off, no seat is bound.
      name = "greeter: present-but-unbound turns nothing on (greetd disabled)";
      ok = !greeterUnbound.services.greetd.enable;
    }
    {
      name = "greeter: enabling it wires greetd to the contract bind command";
      ok =
        greeterBound.services.greetd.enable
        && lib.hasInfix "contract-greeter-bind" greeterBound.services.greetd.settings.default_session.command;
    }
    {
      # ADR-0024 condition 3: the runtime grant is FIXED to the safe set — not an operator choice,
      # impossible to widen here. So a greeter login can never receive a privileged/secret feature.
      name = "greeter: the runtime grant is fixed to greeterGrants (the safe set), unwidenable";
      ok =
        greeterBound.custom.greeter.grants == greeterGrants
        && !(lib.elem "workstation" (lib.attrNames greeterBound.custom.greeter.grants));
    }
    {
      # The home BUILD is the host's binding (ADR-0024 "the host supplies only bindings") —
      # null by default because it needs home-manager, which the contract does not depend on.
      name = "greeter: the home builder is an unbound host binding (null by default)";
      ok = greeterUnbound.custom.greeter.homeBuilder == null;
    }
    {
      # ADR-0031: secret provisioning is off by default (a host opts in on a trusted seat).
      name = "secret provisioning: off by default";
      ok = !greeterUnbound.custom.greeter.secretProvisioning.enable;
    }
    {
      # ADR-0031 / ADR-0015: enabling it on an exposed host is a hard eval error (the seat sees the
      # user's plaintext while activating the home — an agent box must never hold the user's key).
      name = "secret provisioning: enabling it on an exposed host fails an assertion";
      ok = lib.any (
        a: !a.assertion && lib.hasInfix "secretProvisioning" a.message
      ) greeterSecretExposed.assertions;
    }
    {
      # ADR-0030: the contract PINS the Tier-1 eval posture. accept-flake-config=false is the
      # un-widenable linchpin (ADR-0027 applied to eval: a repo cannot self-certify its eval by
      # declaring its own nixConfig); the rest are restrict-eval, no IFD, and a sandboxed build.
      name = "tier1 eval: the posture forbids the repo widening its own eval (accept-flake-config=false)";
      ok = tier1EvalConfig.accept-flake-config == false;
    }
    {
      name = "tier1 eval: the posture restricts eval, bans IFD, and sandboxes the build";
      ok =
        tier1EvalConfig.restrict-eval == true
        && tier1EvalConfig.allow-import-from-derivation == false
        && tier1EvalConfig.sandbox == true;
    }
    {
      # The renderer the greeter uses produces a valid nix.conf body (newline-separated key = value)
      # carrying the un-widenable linchpin — this is the exact string handed to homeBuilder as NIX_CONFIG.
      name = "tier1 eval: the rendered NIX_CONFIG carries the posture verbatim";
      ok =
        let
          rendered = renderNixConfig tier1EvalConfig;
        in
        lib.hasInfix "accept-flake-config = false" rendered && lib.hasInfix "restrict-eval = true" rendered;
    }
    {
      # The greeter EXPOSES the posture it will apply (read-only introspection, like `grants`) — fixed
      # to the contract's tier1EvalConfig, so an operator can audit the eval floor a login builds under.
      name = "greeter: it exposes the pinned tier1 eval posture, unwidenable (== tier1EvalConfig)";
      ok = greeterBound.custom.greeter.tier1EvalConfig == tier1EvalConfig;
    }
  ];
}
