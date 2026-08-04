# ben — a plain cli reference user.
#
# A distinct identity with a thin, contract-pure home. Useful as a co-resident account on a host
# that also binds a privileged user, and as a second borrowable atom for the conformance suite.
#
# Contract-pure (ADR-0008): only contract/home-profile options, no home-manager options, so it
# harvests headlessly in the conformance tracer.
{ ... }:
{
  # The home meta-profiles ben's home offers.
  custom.home.profiles = {
    cli.enable = true;
  };
}
