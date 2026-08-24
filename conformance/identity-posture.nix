# Conformance domain: the OPT-IN identity posture check (issue #35) and, just as load-bearing,
# the fact that `loadIdentity` itself imposes NO hash policy.
#
# ADR-0004 makes the login-credential posture CONDITIONAL and CONSUMER-OWNED: a private repo may
# legitimately ship `$6$` sha512crypt, a public/shared one wants yescrypt (`$y$`) because its hash
# is world-readable. So the strength rule is a repo-authoring choice, not a contract invariant —
# baking yescrypt into the loader would impose one repo's public posture on every consumer,
# including the untrusted roaming single-user flakes the greeter exists for. This domain pins both
# halves: the helper enforces the posture a repo ASKS for, and the loader enforces none.
{
  lib,
  pkgs,
  toolkit,
  loadIdentity,
  mkIdentityPostureCheck,
}:
let
  # The reference fleet's PORTABLE user, borrowed by role through the toolkit's reference seam
  # (../conformance/toolkit.nix). Her identity is the LOADER's own output on the member set the
  # suite derives once, reused rather than re-loaded, so this domain reads the one load already
  # made. She ships `$y$` yescrypt: `examples/users` lives in a PUBLIC repo, and ADR-0004 assigns a
  # public/shared repo the yescrypt posture. So the REAL reference identity is the SATISFYING case
  # here, and the rejecting case is synthetic.
  #
  # That is the right way round. The value the suite proves the loader returns untouched is a real
  # shipped credential, while the hash that must FAIL a posture is a fixture nobody ships — rather
  # than the reverse, which would have required the reference fleet to keep shipping a hash its own
  # ADR tells a public repo not to use, purely to serve a test.
  referenceIdentity = toolkit.referenceUsers.portable.identity;
  yescryptIdentity = referenceIdentity;
  sha512Identity = referenceIdentity // {
    username = "sixto";
    # A syntactically real sha512crypt hash: `$6$<salt>$<hash>`. Nothing verifies it here — the
    # posture is a PREFIX claim about the algorithm, not a crypt() round-trip. Legal under
    # ADR-0004's PRIVATE-repo posture, which is exactly why it must fail a `yescrypt` requirement
    # and pass a `libc` one: the posture is a parameter, not a global rule.
    hashedPassword = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
  };
  # A passwordless identity: no hash at all satisfies no posture — an account with an empty
  # credential must never read as "posture ok". Synthetic on purpose: no reference user has this
  # shape, because this contract delivers "login, dotfiles, the session they need" (ADR-0001), so
  # every reference user carries a credential. An empty `hashedPassword` is the option DEFAULT
  # (identity.nix), i.e. indistinguishable from an unfilled field — which is exactly why it must
  # fail rather than be read as a deliberate "locked account".
  emptyIdentity = referenceIdentity // {
    username = "nopass";
    hashedPassword = "";
  };

  check =
    args:
    mkIdentityPostureCheck (
      {
        inherit pkgs;
      }
      // args
    );
  # The check fails by throwing at eval (a hard, named error), so `tryEval` reads the verdict.
  passes = args: (builtins.tryEval (check args)).success;
in
{
  assertions = [
    {
      name = "identity posture: a yescrypt members satisfies require = \"yescrypt\" (ADR-0004 public/shared)";
      ok = passes {
        identities = [ yescryptIdentity ];
        require = "yescrypt";
      };
    }
    {
      name = "identity posture: a `$6$` identity FAILS require = \"yescrypt\"";
      ok =
        !(passes {
          identities = [ sha512Identity ];
          require = "yescrypt";
        });
    }
    {
      # One offender in an otherwise-yescrypt members fails it — the check is over EVERY identity,
      # which is why a repo derives its members rather than hardcoding a list.
      name = "identity posture: one non-yescrypt identity fails the whole members";
      ok =
        !(passes {
          identities = [
            yescryptIdentity
            sha512Identity
          ];
          require = "yescrypt";
        });
    }
    {
      # The posture is a PARAMETER, not a hardcoded rule: the same `$6$` identity the yescrypt
      # requirement rejects is legal under the private-repo posture ADR-0004 allows.
      name = "identity posture: the same `$6$` identity passes require = \"libc\" (the posture is a parameter, ADR-0004 private repo)";
      ok = passes {
        identities = [ sha512Identity ];
        require = "libc";
      };
    }
    {
      name = "identity posture: an empty hashedPassword satisfies no posture, not even \"libc\"";
      ok =
        !(passes {
          identities = [ emptyIdentity ];
          require = "libc";
        });
    }
    {
      # loadIdentity returns the identity.json RAW, and hashedPassword is OPTIONAL — so an entry
      # may carry no such attribute at all. That must reach the check's own verdict (an absent
      # credential fails the posture), not an `attribute 'hashedPassword' missing` crash.
      name = "identity posture: an identity with no hashedPassword field at all fails the posture (raw JSON, optional field)";
      ok =
        !(passes {
          identities = [ (builtins.removeAttrs referenceIdentity [ "hashedPassword" ]) ];
          require = "libc";
        });
    }
    {
      # A check over nothing would report "ok" forever — the same vacuity trap the confinement
      # check's positive control closes.
      name = "identity posture: an empty members is a hard error, never a vacuous pass";
      ok =
        !(passes {
          identities = [ ];
          require = "yescrypt";
        });
    }
    {
      name = "identity posture: an unknown posture name is a loud error (typo-net)";
      ok =
        !(passes {
          identities = [ yescryptIdentity ];
          require = "yescrpyt";
        });
    }
    {
      # THE ADR-0004 claim: the loader carries no policy. This must be driven by a NON-yescrypt
      # hash going through the REAL loader, or it proves nothing — a loader that DID bake in the
      # public-repo posture would accept a `$y$` identity just as happily, so asserting over
      # `referenceIdentity` (now yescrypt, since examples/users is a public repo) would pass
      # vacuously. Hence a dedicated `$6$` fixture, loaded rather than hand-written: the loader
      # neither rejected it (a hash policy would throw, taking this whole domain with it) nor
      # rewrote it. A private repo is not forced onto a public repo's posture.
      name = "loadIdentity imposes no hash policy: it returns a `$6$` identity.json unchanged (ADR-0004, posture is consumer-owned)";
      ok = lib.hasPrefix "$6$" (loadIdentity ./fixtures/private-repo-identity.json).hashedPassword;
    }
  ];

  # Execution proof: the check a repo wires into `checks.<system>` is a real derivation that BUILDS.
  drvs.mkIdentityPostureCheck = check {
    identities = [ yescryptIdentity ];
    require = "yescrypt";
    name = "conformance-identity-posture";
  };
}
