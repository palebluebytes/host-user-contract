# ben's real-home signing reaction — the home-side of the contract's grant→degrade pattern.
#
# This is the ONE home-side pattern the contract documents (its home.nix docstring: branch READ-ONLY
# on hostFacts.granted.<f> to pick a backend). ben's home wires its signing marker ONLY where the
# host granted signing, and silently does nothing where it did not (ADR-0002). A real backend
# (programs.git.signing.*) would go exactly here; the marker stands in so the reference stays
# package-light and the reaction is observable.
#
# It lives in ben's dir but is loaded ONLY into the REAL home build (the flake's mkHome `extra`),
# NOT via ben/home.nix — because it reads hostFacts and sets a home-manager option (home.file),
# neither of which exists in the headless tracer. home.nix stays contract-pure (ADR-0008); this is
# the real-build-only reaction beside it.
{
  hostFacts,
  config,
  lib,
  ...
}:
{
  home.file.".signing-key-configured" = lib.mkIf (hostFacts.granted.signing.enable or false) {
    text = "signing backend wired for ${config.identity.name}";
  };
}
