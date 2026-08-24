# Conformance domain: the reference greeter module — the NORTH-STAR path — and the Tier-1
# restricted-eval posture it applies. Eval-level claims (the present-but-unbound litmus, the FIXED safe-set
# grant, the pinned eval posture) plus two EXECUTION proofs built as sub-derivations: the eval-free
# auth flow and the restricted-eval enforcement. Returns those drvs so ./default.nix builds them.
{
  lib,
  pkgs,
  toolkit,
  greeterModule,
  greeterAffordances,
  runsWith,
  safeSet,
  tier1EvalConfig,
  renderNixConfig,
}:
let
  inherit (toolkit) eval;

  # The opt-in greetd + eval-free-bind + provision module. Present-but-UNBOUND must turn nothing
  # on; ENABLED it wires greetd to the contract bind command, conferring the (empty) safe set.
  greeterUnbound = eval [ greeterModule ];
  seat =
    modes:
    eval [
      greeterModule
      {
        contract.modes = modes;
        contract.greeter.enable = true;
        contract.greeter.homeBuilder = "/run/current-system/sw/bin/true";
      }
    ];
  # A seat WITH a display, and one without. The pair is the point: what a greeter offers a stranger
  # is now a property of the machine, so these two must differ — and before the machine capability
  # existed they could not.
  greeterBound = seat [ "gui" ];
  greeterHeadless = seat [ ];

  # The auth-flow EXECUTION test (the CANONICAL eval-free auth): pull the
  # actual shipped `contract-greeter-auth` script out of the enabled greeter's systemPackages and
  # run it against the PORTABLE reference user's real identity.json. It must accept the right
  # password and reject a wrong one / a mismatched username — having read only data (`jq` + libc
  # crypt), never the user's Nix. Tier 2 isolates the password check (no signature); the Tier-1
  # block then exercises the signature branch with a real SSH key (good signature accepts,
  # untrusted-key and absent signatures reject).
  authScript =
    lib.findFirst (p: lib.hasInfix "contract-greeter-auth" (p.name or ""))
      (throw "conformance: contract-greeter-auth not found in the greeter's systemPackages")
      greeterBound.environment.systemPackages;
  # The reference fleet's PORTABLE user — her real directory, her real username and the cleartext
  # behind her real `hashedPassword` — borrowed by role through the toolkit's reference seam
  # (../conformance/toolkit.nix), so this proof names no path and no person.
  inherit (toolkit) referenceSecret;
  portable = toolkit.referenceUsers.portable;
  portableSrc = portable.dir;
  # The username the AUTH SCRIPT matches on is the one inside `identity.json`, not the directory
  # name — so this reads the identity, and ./members.nix is what keeps the two spellings honest.
  portableName = portable.identity.username;
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
        src=${portableSrc}

        echo "# right password ⇒ accepts"
        printf '%s\n' '${referenceSecret}' \
          | contract-greeter-auth "$src" ${portableName} tier2 /dev/null

        echo "# wrong password ⇒ rejects"
        if printf '%s\n' 'wrong-password' \
          | contract-greeter-auth "$src" ${portableName} tier2 /dev/null 2>/dev/null; then
          echo "FAIL: a wrong password was accepted" >&2; exit 1
        fi

        echo "# username mismatch ⇒ rejects (no impersonation)"
        if printf '%s\n' '${referenceSecret}' \
          | contract-greeter-auth "$src" someone-else tier2 /dev/null 2>/dev/null; then
          echo "FAIL: a mismatched username was accepted" >&2; exit 1
        fi

        # --- sha512crypt hash format ---
        # The auth script re-hashes with libc crypt (via perl), which is ALGORITHM-AGNOSTIC: it
        # reads the stored `$id$` prefix and applies the matching KDF, exactly as /etc/shadow does.
        # Proving that needs both branches driven, so the two fixtures are deliberately split by
        # algorithm:
        #   - the reference user above carries $y$ yescrypt — the REAL shipped identity, since
        #     examples/users is a public repo, and a public repo takes the yescrypt posture;
        #   - this synthetic fixture carries $6$ sha512crypt — legal under the PRIVATE-repo
        #     posture, and the branch a roaming user from a private repo will arrive with.
        # A format-handling regression on either therefore cannot pass conformance unnoticed. The
        # cleartext is the same canonical secret; only the stored format differs.
        mkdir sha512-src
        cat > sha512-src/identity.json <<'IDENTITY'
        {
          "name": "Sha512 Fixture",
          "username": "sixto",
          "hashedPassword": "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/"
        }
        IDENTITY

        echo "# sha512crypt: right password ⇒ accepts (the \$6\$ branch)"
        # A LITERAL, not `referenceSecret`: the hash above is a frozen blob, so this cleartext
        # cannot follow the reference fleet rotating its own. It is the same secret today and
        # says so in prose; tying it to the atom would break this fixture the day that changed.
        printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth sha512-src sixto tier2 /dev/null

        echo "# sha512crypt: wrong password ⇒ rejects"
        if printf '%s\n' 'wrong-password' \
          | contract-greeter-auth sha512-src sixto tier2 /dev/null 2>/dev/null; then
          echo "FAIL: a wrong password was accepted against the sha512crypt fixture" >&2; exit 1
        fi

        # --- Tier 1: the repo must be SIGNED by a host-trusted key ---
        # Build a signed source: the example identity.json + an SSH signature over the tree
        # manifest (exactly what the auth script recomputes and verifies), plus the allowed-signers
        # file a host would derive from contract.greeter.trustedSigners.
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
        printf '%s\n' '${referenceSecret}' \
          | contract-greeter-auth signed ${portableName} tier1 trusted-signers

        echo "# tier1: a signature by an UNTRUSTED key ⇒ rejects"
        if printf '%s\n' '${referenceSecret}' \
          | contract-greeter-auth signed ${portableName} tier1 attacker-signers 2>/dev/null; then
          echo "FAIL: a signature by an untrusted key was accepted" >&2; exit 1
        fi

        echo "# tier1: no signature at all ⇒ rejects"
        if printf '%s\n' '${referenceSecret}' \
          | contract-greeter-auth "$src" ${portableName} tier1 trusted-signers 2>/dev/null; then
          echo "FAIL: an unsigned repo was accepted at tier1" >&2; exit 1
        fi

        echo "eval-free auth flow OK" ; touch $out
      '';

  # The restricted-eval EXECUTION test: prove the contract's PINNED Tier-1 posture, when
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
in
{
  drvs = {
    greeterAuthFlow = authFlowTest;
    tier1RestrictedEval = restrictedEvalTest;
  };

  assertions = [
    {
      # What a greeter affords: default-open over the safe set — it enables exactly
      # the runtime-eligible features, no operator choice, no more.
      name = "greeterAffordances: exactly the safe set (default-open, nothing beyond it)";
      ok =
        (lib.sort (a: b: a < b) (lib.attrNames greeterAffordances) == lib.sort (a: b: a < b) safeSet)
        && lib.all (n: greeterAffordances.${n}) (lib.attrNames greeterAffordances);
    }
    {
      # A greeter affords AT MOST the safe set, so a
      # runtime-bound user can never receive a privileged-group feature — escalation is
      # impossible by construction, not by a deny rule.
      name = "greeterAffordances: affords no privileged-group feature (no escalation)";
      ok = lib.all (f: !(lib.elem f (lib.attrNames greeterAffordances))) [
        "containers"
        "sudo"
        "virtualization"
        "nix-daemon"
      ];
    }
    {
      # The litmus: the greeter ships in the eval but a host that does not enable it gets
      # nothing — greetd stays off, no seat is bound.
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
      # The runtime affordance is FIXED to the safe set — not an operator choice,
      # impossible to widen here. So a greeter login can never receive a privileged feature.
      name = "greeter: what a seat affords is fixed to the safe set, unwidenable";
      ok =
        greeterBound.contract.greeter.affordances == greeterAffordances
        && !(lib.elem "containers" (lib.attrNames greeterBound.contract.greeter.affordances));
    }
    {
      # …and therefore what a seat RUNS. Derived from the affordances by the same function a
      # declarative bind uses, so the two paths cannot come to different answers about what this
      # machine can run — which is what makes a walk-up login and a declared one the same
      # experience. Because `gui` is the one feature conferring no privileged group, a greeter seat
      # runs the graphical mode for everybody: "gui by default", with nothing declared on either
      # side.
      name = "greeter: the modes a seat runs are derived from what it affords (the same derivation a bind uses)";
      ok =
        greeterBound.contract.greeter.runs == runsWith [ "gui" ]
        && lib.elem "gui" greeterBound.contract.greeter.runs;
    }
    {
      # THE BUG THE MACHINE/PERSON SPLIT FIXES, pinned so it cannot come back: a greeter on a
      # machine that declares no display must not claim to run a graphical session. Before
      # `contract.modes` existed there was no way to express this — the run set was a CONSTANT
      # (`runsFor safeSet`), identical on every host — so a headless seat would select a walk-up
      # user's gui home and fail at the `nix build`, at a login prompt, with a raw error.
      name = "greeter: a seat that declares no display runs the floor alone";
      ok = greeterHeadless.contract.greeter.runs == runsWith [ ];
    }
    {
      # SELECTION IS SINGLE-SOURCED. The greeter does not re-spell `selectModeOver` in shell: it
      # ships `contract-select-mode`, which evaluates the contract's own kernel at login. The
      # wiring is what needs asserting here — that the tool is actually on the seat — because a
      # rule with two spellings is a rule with two behaviours, and the one it replaced had already
      # drifted on the two-incomparable-modes case. The kernel's own cases are proven at eval level
      # in ./modes.nix; that the greeter USES it is proven by the bind-loop VM.
      name = "greeter: a seat ships the mode-selection evaluator (selection is not re-spelled in shell)";
      ok = lib.any (
        p: lib.hasInfix "contract-select-mode" "${p}"
      ) greeterBound.environment.systemPackages;
    }
    {
      # The home BUILD is the host's binding ("the host supplies only bindings") —
      # null by default because it needs home-manager, which the contract does not depend on.
      name = "greeter: the home builder is an unbound host binding (null by default)";
      ok = greeterUnbound.contract.greeter.homeBuilder == null;
    }
    {
      # The contract PINS the Tier-1 eval posture. accept-flake-config=false is the
      # un-widenable linchpin (a repo cannot self-certify its eval by
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
      ok = greeterBound.contract.greeter.tier1EvalConfig == tier1EvalConfig;
    }
  ];
}
