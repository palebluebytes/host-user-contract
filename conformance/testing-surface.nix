# Conformance domain: the TESTING SURFACE the contract publishes (issue #88) — `testing.mkSeatHarness`,
# the seat-VM harness this suite's ten runtime proofs are built on, named at the flake surface so the
# reference host fleet can boot a contract seat without naming a path inside this directory.
#
# WHAT THIS CAN AND CANNOT CATCH. The output is this directory's own harness handed onward
# (./testing.nix), so nothing here can drift while that stays true — which is the point, and also why
# the claims below look tautological read against today's `testing.nix`. What they gate is that it
# stays true: a `testing.nix` (or a `flake.nix`) repointed at a trimmed wrapper or a second copy of
# the seat host — the obvious "fix" the day the fleet wants a seat the suite does not build — passes
# every other check in this repo, because nothing else compares the two. It would fail here.
#
# The alternative was to let the sibling fleet's own CI be the gate, which is the arrangement issue
# #88 closed: the contract's shipped surface must break in the contract's own suite.
#
# `mkSeatVM` is claimed only to BE published: what it builds is claimed by the eleven seat VMs built
# through it, and calling it here would boot a twelfth.
{
  lib,
  pkgs,
  system,
  testing,
  contractModule,
  greeterModule,
}:
let
  args = {
    inherit
      pkgs
      system
      contractModule
      greeterModule
      ;
  };
  # The harness as a CONSUMER reaches it: through the flake output, handed `pkgs` and the modules it
  # composes, because neither is an input of the contract flake (ADR-0002).
  published = testing.mkSeatHarness args;
  # …and as this suite reaches it: the file itself, which is what every VM file in this directory
  # imports. The suite owns where that file lives; the output above is how anything else asks for it.
  own = import ./seat-vm.nix args;
in
{
  assertions = [
    {
      name = "testing.mkSeatHarness: publishes `mkSeatVM` and the seat fixtures a VM varies against";
      ok =
        lib.attrNames published == [
          "activationStub"
          "mkSeatVM"
          "signer"
          "signerPub"
          "testIdentity"
        ];
    }
    {
      # Ordered after the shape claim, and read with `or null` for the same reason: a harness missing
      # a fixture must be reported by the claim above, not crash this one — an `attribute missing`
      # inside an `ok` propagates as an eval error, and this suite reports verdicts.
      #
      # The inert data by equality, the two derivations by store path, which is what makes a copy
      # visible: a re-authored fixture lands on a different `.drv` unless it is identical byte for
      # byte, in which case there is nothing to drift.
      name = "testing.mkSeatHarness: the published fixtures ARE this suite's, not a second copy";
      ok =
        (published.testIdentity or null) == own.testIdentity
        && (published.signerPub or null) == own.signerPub
        && (published.signer.drvPath or null) == own.signer.drvPath
        && (published.activationStub.drvPath or null) == own.activationStub.drvPath;
    }
  ];
}
