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
# The binding (bindUser) injects the user's `identity` into this home and exposes
# `hostFacts` + `pkgs` in scope — the home never loads identity.json itself (ADR-0025: the
# binding is the single loader). A real home module reads `config.identity.{name,email}` for
# its dotfiles (e.g. `programs.git.userName`) and branches READ-ONLY on `hostFacts` — never
# raw osConfig, never hostName (ADR-0018), e.g. `hostFacts.granted.signing.enable` to pick a
# git signing backend. Those touch home-manager options, which exist only in the full home
# build (the flake below / the host's home-manager), not in bindUser's contract-only harvest
# eval — so this fixture, which must evaluate in both, only emits its request.
{ ... }:
{
  # A host-affecting REQUEST: this user wants an X11 session. It is inert until a host
  # GRANTS gui — then bindUser harvests it and the gui-session union offers X11 (ADR-0019).
  # The user only asks; the host decides and writes.
  contract.requests.gui.session = "x11";

  # The user's DESKTOP choice (ADR-0029): a free-form, DE-agnostic name that travels with the home.
  # Still just a request here (contract-pure, so the tracer harvests it); the contract's
  # homeModules.greeterDesktop helper materialises it to ~/.contract-desktop in a real home build,
  # where the greeter's launcher reads it and maps it to a desktop the seat offers (else its default).
  contract.requests.gui.desktop = "plasma";
}
