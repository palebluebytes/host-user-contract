# ben — a plain cli reference user.
#
# A distinct identity with a thin, contract-pure home. Useful as a co-resident account on a host
# that also binds a privileged user, and as a second borrowable atom for the conformance suite.
#
# Contract-pure (ADR-0008): only contract/home-profile options, no home-manager options, so it
# harvests headlessly in the conformance tracer.
{ ... }:
{
  # ben declares no `contract.wants` at all, so his offer is the safe-set default (ADR-0028): he
  # asks for nothing privileged and takes a seat wherever one is afforded. Contrast svc, which
  # opts OUT of gui explicitly.
  #
  # The home meta-profiles ben's home offers.
  custom.home.profiles = {
    cli.enable = true;
  };
}
