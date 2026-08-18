# ben — a plain cli reference user.
#
# A distinct identity with a thin, contract-pure home. Useful as a co-resident account on a host
# that also binds a privileged user, and as a second borrowable atom for the conformance suite.
#
# Contract-pure (ADR-0008): no home-manager options at all, so it harvests headlessly in the
# conformance tracer. And nothing else either — ben is the members' MINIMAL home, which is a real
# shape a users repo has and worth one fixture.
{ ... }:
{
  # The MINIMAL declaration (ADR-0032): one line, naming the one session shape this home runs in.
  # ben is a terminal user, so `cli` is the whole of it — and because there is no default, saying
  # nothing would make him uninstallable rather than quietly cli.
  contract.supports.cli = true;

  # ben declares no `contract.wants` at all, so his offer is the safe-set default (ADR-0028): he
  # asks for nothing privileged and takes a seat wherever one is afforded. Contrast svc, which
  # opts OUT of gui explicitly.
  #
  # He declares no `custom.home.profiles.*` either — the contract writes those from the mode it
  # built him for (the rule is stated once, in `home-profiles.nix`), and he has no content to gate
  # on them anyway.
}
