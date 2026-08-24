# This directory's EXPORT LIST — the one file under `conformance/` that anything outside it names,
# published by ../flake.nix as the `testing` output (issue #88).
#
# The rest of the suite is the adversarial oracle (ADR-0022): a proof, not a facility, and a proof has
# no consumers. What it does own is a facility — the seat-VM harness its ten runtime proofs are
# built on — and one consumer outside the contract needs it: the reference host fleet's end-to-end
# greeter test, which boots a contract seat to activate a real home-manager home (a thing the contract
# flake cannot build itself, ADR-0002).
#
# The indirection is the point. Before this file, that test interpolated `conformance/seat-vm.nix`
# into a string, so a suite that reorganised its own directory broke a sibling flake. Now this file is
# the interface and the layout behind it is the suite's own: a caller inside this directory imports
# the harness by relative path, exactly as it did, and moving the file is an edit under `conformance/`.
{
  # mkSeatHarness `{ pkgs; system; contractModule; greeterModule ? null }` → `{ mkSeatVM; signer;
  # signerPub; testIdentity; activationStub; }` — the standing seat-host scaffolding plus the fixtures
  # a seat VM varies against. `pkgs` and the modules are ARGUMENTS, never inputs (ADR-0002), which is
  # the same shape the check kit's helpers take and for the same reason. ./seat-vm.nix carries the
  # signature of `mkSeatVM` itself and what each fixture is for.
  mkSeatHarness = import ./seat-vm.nix;
}
