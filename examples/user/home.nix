# Example user home module (ADR-0007, issue #5) — the shape a user repo exports.
#
# It is a contract-PARAMETERIZED home-manager module: it USES contract-declared options
# and EMITS host-affecting requests in the `contract.requests` namespace, but imports NO
# contract and writes NO system config (it has no system channel — the confinement is
# structural, ADR-0002). Something else (bindUser, or the standalone flake below) supplies
# the contract umbrella, `pkgs`, and the read-only `hostFacts` projection.
#
# Deliberately contract-pure: it sets only contract/home options, never home-manager's own
# `home.*` (username/stateVersion live in the standalone flake's module list), so the same
# module evaluates headlessly against just the contract umbrella when bindUser harvests its
# requests — no home-manager needed for the harvest (ADR-0008's package-free contract).
# The binding (bindUser) injects the user's `identity` into this home and exposes
# `hostFacts` + `pkgs` in scope — the home never loads identity.json itself (ADR-0009: the
# binding is the single loader). A real home module reads `config.identity.{name,email}` for
# its dotfiles (e.g. `programs.git.userName`) and branches READ-ONLY on `hostFacts` — never
# raw osConfig, never hostName (ADR-0002), e.g. `hostFacts.granted.signing.enable` to pick a
# git signing backend. Those touch home-manager options, which exist only in the full home
# build (the flake below / the host's home-manager), not in bindUser's contract-only harvest
# eval — so this fixture, which must evaluate in both, only emits its request.
{ ... }:
{
  # The user's DESKTOP choice (ADR-0013): a free-form, DE-agnostic name that travels with the home.
  # It is inert until a host GRANTS gui — then bindUser harvests it and the seat maps it to a real
  # desktop (else its default). The session type (wayland/x11) is DERIVED from this desktop, never
  # expressed as a user preference (ADR-0018): the gui-session union reads the desktop's mapped type.
  # Still just a request here (contract-pure, so the tracer harvests it); the contract's
  # homeModules.greeterDesktop helper materialises it to ~/.contract-desktop in a real home build,
  # where the greeter's launcher reads it.
  contract.requests.gui.desktop = "plasma";
}
