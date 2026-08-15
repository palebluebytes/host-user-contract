# Conformance domain: the OPT-IN identity posture check (issue #35) and, just as load-bearing,
# the fact that `loadIdentity` itself imposes NO hash policy.
#
# ADR-0019 makes the login-credential posture CONDITIONAL and CONSUMER-OWNED: a private repo may
# legitimately ship `$6$` sha512crypt, a public/shared one wants yescrypt (`$y$`) because its hash
# is world-readable. So the strength rule is a repo-authoring choice, not a contract invariant —
# baking yescrypt into the loader would impose one repo's public posture on every consumer,
# including the untrusted roaming single-user flakes the greeter exists for. This domain pins both
# halves: the helper enforces the posture a repo ASKS for, and the loader enforces none.
{
  lib,
  pkgs,
  toolkit,
  mkIdentityPostureCheck,
}:
let
  # `referenceIdentity` IS `loadIdentity examples/users/users/ada/identity.json` (../conformance/
  # toolkit.nix) — the loader's own output, reused rather than re-loaded, so this domain reads the
  # one load the suite already makes. Ada ships `$6$` (a private-repo-legal hash, ADR-0019), which
  # makes the same value both the loader's no-policy witness and the rejecting case under a
  # yescrypt requirement.
  inherit (toolkit) referenceIdentity;
  sha512Identity = referenceIdentity;
  yescryptIdentity = referenceIdentity // {
    username = "yara";
    # A syntactically real yescrypt hash: `$y$<params>$<salt>$<hash>`. Nothing verifies it here —
    # the posture is a PREFIX claim about the algorithm, not a crypt() round-trip.
    hashedPassword = "$y$j9T$sQ8Zx0mHXqk4hM1p2rE3d.$hZTLbC4y6r0Wl9nQvJ7sKxYf1TdA2mR8eN5uG3bV0oC";
  };
  # A passwordless identity (the reference roster's `svc` shape): no hash at all satisfies no
  # posture — an account with an empty credential must never read as "posture ok".
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
      name = "identity posture: a yescrypt roster satisfies require = \"yescrypt\" (ADR-0019 public/shared)";
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
      # One offender in an otherwise-yescrypt roster fails it — the check is over EVERY identity,
      # which is why a repo derives its roster rather than hardcoding a list.
      name = "identity posture: one non-yescrypt identity fails the whole roster";
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
      # requirement rejects is legal under the private-repo posture ADR-0019 allows.
      name = "identity posture: the same `$6$` identity passes require = \"libc\" (the posture is a parameter, ADR-0019 private repo)";
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
      name = "identity posture: an empty roster is a hard error, never a vacuous pass";
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
      # THE ADR-0019 claim: the loader carries no policy. `referenceIdentity` is what
      # `loadIdentity` RETURNED for a real identity.json shipping a `$6$` hash — the loader
      # neither rejected it (a hash policy would throw, taking this whole domain with it) nor
      # rewrote it. A private repo is not forced onto a public repo's posture.
      # The corollary — that this same loaded identity IS rejected once a repo asks for yescrypt —
      # is the `$6$`-fails-yescrypt claim above, driven by this very value.
      name = "loadIdentity imposes no hash policy: it returns a `$6$` identity.json unchanged (ADR-0019, posture is consumer-owned)";
      ok = lib.hasPrefix "$6$" referenceIdentity.hashedPassword;
    }
  ];

  # Execution proof: the check a repo wires into `checks.<system>` is a real derivation that BUILDS.
  drvs.mkIdentityPostureCheck = check {
    identities = [ yescryptIdentity ];
    require = "yescrypt";
    name = "conformance-identity-posture";
  };
}
