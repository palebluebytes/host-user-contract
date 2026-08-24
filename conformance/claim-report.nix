# Conformance domain: the CLAIM REPORT — the shape three sites in this repo were spelling by hand.
#
# A claim report runs a list of named verdicts, prints an `ok`/`FAIL` line each, threads execution
# proofs in as build inputs, and fails the build if anything failed. That is the technique ADR-0025
# reserves the check kit for: the contract ships how a consumer says what its own repo proved, not
# what it proved.
#
# What this domain has to prove is unusual, and worth naming: BOTH DIRECTIONS OF A BUILD VERDICT. A
# reporter that never fails is the purest vacuity there is — every claim green, forever, and the
# output reads exactly like a suite that works. So an eval-time claim that "a failing claim set is
# refused" would prove nothing: the refusal is in the BUILDER, and the only way to observe a builder
# refusing is to build it and watch it fail. `pkgs.testers.testBuildFailure` is what makes that
# expressible — it builds a derivation expected to fail and captures its log, so "this cannot build"
# becomes a derivation that CAN.
#
# Two execution proofs, therefore, and they are the load-bearing part of this file:
#
#   - a passing claim set builds, with a proof threaded in;
#   - a FAILING claim set does not, and the failure NAMES the claim that failed.
#
# THE WIRING — "building the report builds the proofs" — is claimed at EVAL instead, and the three
# ways to claim it in a BUILD were each tried and rejected. Written down because each looks like it
# should work:
#
#   testBuildFailure on a report whose proof cannot build — it rewrites the BUILDER of the
#     derivation handed to it, and a failing input never reaches that builder: Nix fails a
#     dependency first and the dependent is never run. Nothing is left to observe.
#   reading the report's own `.drv` for the proof in its `inputDrvs` — this interrogates the actual
#     mechanism, and it is FORBIDDEN in pure evaluation mode ("access to absolute path … is
#     forbidden"), which is the mode a flake check evaluates in.
#   having the report's builder test that each proof path is present in its sandbox — sound, and
#     undrivable: the only material that could make it fail is a proof that is not a derivation,
#     which the guard below refuses one step earlier. A guard no test can reach is not a guard.
#
# So the two eval claims close it between them: the proof reaches the derivation AS THE DERIVATION
# — identity, which is what carries the string context Nix turns into an input edge — and a proof
# that is NOT a derivation is refused, which is the hole the first claim would otherwise leave.
#
# SELF-HOSTING, deliberately: this domain's own claims are reported by the very function it claims
# about, through the suite's collector. That is not circular — a broken reporter fails the two
# builds above, which is where the verdict actually lives.
{
  lib,
  pkgs,
  mkClaimReport,
}:
let
  # A claim set that passes, and one that does not. Two claims each, so the rendering is exercised
  # over more than one line and a FAIL is seen beside an `ok` rather than alone.
  passing = [
    {
      name = "the first thing this fixture claims";
      ok = true;
    }
    {
      name = "the second thing this fixture claims";
      ok = true;
    }
  ];
  # The offender's name is distinctive on purpose: the failing-build proof below greps the captured
  # log for it, so "the report named what failed" is checked rather than assumed.
  failingClaimName = "this-fixture-claim-is-meant-to-fail";
  failing = passing ++ [
    {
      name = failingClaimName;
      ok = false;
    }
  ];

  # A trivial execution proof to thread in.
  goodProof = pkgs.runCommand "conformance-claim-report-proof" { } "touch $out";

  report =
    args:
    mkClaimReport (
      {
        inherit pkgs;
        name = "conformance-claim-report-probe";
        title = "claim-report probe";
        claims = passing;
      }
      // args
    );
  # Does the report REFUSE this material at eval? Forced to a `.drv` path, so a lazily-returned
  # derivation cannot make a refusal look like a pass.
  refused = args: !(builtins.tryEval (report args).drvPath).success;
in
{
  assertions = [
    {
      # THE anti-vacuity trap, and the reason this function has a guard at all: a reporter folded
      # over nothing prints a header, touches its output and reports success — green, with no work
      # done and nothing to read.
      name = "mkClaimReport: an empty claim list is refused (a report over nothing would print a header and pass)";
      ok = refused { claims = [ ]; };
    }
    {
      # …and the control for it: the trap is about the CLAIMS, not about the proofs. The reference
      # host fleet's report carries no execution proof at all, so an over-eager guard here would
      # refuse a real call site.
      name = "mkClaimReport: an empty PROOF set is fine — a report may be all eval claims (the host fleet's is)";
      ok = !(refused { proofs = { }; });
    }
    {
      # A claim the report cannot READ must not be reported as a verdict. Without this the module
      # system's own "attribute 'ok' missing" is what a consumer meets, from inside a function they
      # did not write.
      name = "mkClaimReport: a claim with no verdict is refused, rather than throwing 'attribute ok missing'";
      ok = refused {
        claims = [ { name = "a claim carrying no ok field"; } ];
      };
    }
    {
      name = "mkClaimReport: a claim with no name is refused — an unnameable verdict cannot be reported";
      ok = refused {
        claims = [ { ok = true; } ];
      };
    }
    {
      # A non-boolean verdict is the quiet one: `ok = "yes"` is truthy to a reader and a type error
      # to `if`, and a filter that used `!a.ok` would throw rather than diagnose.
      name = "mkClaimReport: a non-boolean verdict is refused (`ok = \"yes\"` is not a verdict)";
      ok = refused {
        claims = [
          {
            name = "a claim whose verdict is a string";
            ok = "yes";
          }
        ];
      };
    }
    {
      name = "mkClaimReport: a passing claim set yields a derivation";
      ok = lib.hasSuffix ".drv" (report { }).drvPath;
    }
    {
      # The report is named by its CALLER (ADR-0025's posture for the whole kit: a consumer labels a
      # check it owns). Two reports in one `nix flake check` output are told apart by this.
      name = "mkClaimReport: the derivation takes the caller's own name";
      ok = (report { }).name == "conformance-claim-report-probe";
    }
    {
      # THE WIRING (see the header for why this is an eval claim). The proof reaches the derivation
      # as the derivation itself — identity, not just presence — which is what carries the string
      # context that makes it a build input. A proof rendered only into the report TEXT would be
      # decoration: printed, depended on by nothing, reporting `ok` without having run.
      name = "mkClaimReport: an execution proof reaches the derivation AS the derivation (so it is a build input, not text)";
      ok =
        let
          # Asked as `?` first: a report that dropped its proofs entirely would make the identity
          # comparison THROW rather than report false, and a domain that errors says less than one
          # that fails.
          r = report { proofs.someProof = goodProof; };
        in
        (r ? someProof) && r.someProof == goodProof;
    }
    {
      # …and the hole that claim leaves, closed: a proof that is not a derivation becomes a plain
      # environment variable, which is exactly the decoration above. Refused, so the wiring claim
      # cannot be satisfied by something that never runs.
      name = "mkClaimReport: an execution proof that is not a derivation is refused (it would never run)";
      ok = refused { proofs.notADerivation = "/nix/store/nothing-here"; };
    }
    {
      # The proofs are read BY NAME, so material with no names must be refused before the rendering
      # reads any — the same order the claims themselves are guarded in.
      name = "mkClaimReport: a `proofs` that is not an attrset is refused (a proof is read by its name)";
      ok = refused { proofs = [ goodProof ]; };
    }
    {
      # A report line is ONE line, and this is the claim that keeps the rendering honest rather than
      # merely tidy: a name carrying a line that reads `EOF` would close the report's own heredoc
      # and hand whatever followed it to the shell.
      name = "mkClaimReport: a claim name spanning more than one line is refused (a report line is one line)";
      ok = refused {
        claims = [
          {
            name = "a name that carries\nEOF\nrm -rf /";
            ok = true;
          }
        ];
      };
    }
  ];

  drvs = {
    # DIRECTION ONE — a passing claim set, with a proof threaded in, builds.
    claim-report-passes = report { proofs.someProof = goodProof; };

    # DIRECTION TWO — a failing claim actually fails the build, and the failure NAMES it. Both
    # halves matter: a report that failed for any other reason (a typo in the script, a missing
    # tool) would satisfy "it failed" while telling a reader nothing.
    claim-report-fails-a-failing-claim =
      let
        refusal = pkgs.testers.testBuildFailure (report {
          claims = failing;
        });
      in
      pkgs.runCommand "conformance-claim-report-fails-a-failing-claim" { } ''
        log=${refusal}/testBuildFailure.log
        grep -q '${failingClaimName}' "$log" || {
          echo "the report failed, but its output never names the claim that failed — a reader is told only that something broke" >&2
          cat "$log" >&2
          exit 1
        }
        touch $out
      '';
  };
}
