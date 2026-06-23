# Example user home module (ADR-0023, issue #5) — the shape a user repo exports.
#
# It is a contract-PARAMETERIZED home-manager module: it USES contract-declared options
# and EMITS host-affecting requests in the `contract.requests` namespace, but imports NO
# contract and writes NO system config (it has no system channel — the confinement is
# structural, ADR-0018). Something else (bindUser, or the standalone flake below) supplies
# the contract umbrella, `pkgs`, and the read-only `hostFacts` projection.
#
# Deliberately contract-pure: it sets only contract/home options, never home-manager's own
# `home.*` (username/stateVersion live in the standalone flake's module list), so the same
# module evaluates headlessly against just the contract umbrella when bindUser harvests its
# requests — no home-manager needed for the harvest (ADR-0024's package-free contract).
# The binding injects `hostFacts` (and `pkgs`) into scope for READ-ONLY host adaptation —
# never raw osConfig, never hostName (ADR-0018). A real home module destructures
# `{ hostFacts, ... }` and branches its dotfiles on semantic facts, e.g.
# `hostFacts.granted.signing.enable` to pick a git signing backend. Requests stay
# host-independent, so this fixture needs neither and takes none.
{ ... }:
{
  # A host-affecting REQUEST: this user wants an X11 session. It is inert until a host
  # GRANTS gui — then bindUser harvests it and the gui-session union offers X11 (ADR-0019).
  # The user only asks; the host decides and writes.
  contract.requests.gui.session = "x11";
}
