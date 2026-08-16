# ben — a plain cli reference user.
#
# A distinct identity with a thin, contract-pure home. Useful as a co-resident account on a host
# that also binds a privileged user, and as a second borrowable atom for the conformance suite.
#
# Contract-pure (ADR-0008): no home-manager options at all, so it harvests headlessly in the
# conformance tracer. And nothing else either — ben is the roster's MINIMAL home, which is a real
# shape a users repo has and worth one fixture.
{ ... }:
{
  # ben declares no `contract.wants` at all, so his offer is the safe-set default (ADR-0028): he
  # asks for nothing privileged and takes a seat wherever one is afforded. Contrast svc, which
  # opts OUT of gui explicitly.
  #
  # He declares no `custom.home.profiles.*` either — it is a switch a home gates its OWN content on
  # (the rule is stated once, in the contract's `home-profiles.nix`), and he has none to gate.
}
