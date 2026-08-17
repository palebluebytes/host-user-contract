# Home meta-profile options — part of the host↔user contract (ADR-0001).
# Declared by the home umbrella module as `custom.home.profiles.*`.
# The single home-profile vocabulary: the meta-profiles (cli/gui) a user's home gates its own
# content on. Declaring them in one place keeps the vocabulary from scattering; the user's own
# leaf modules act on it.
#
# It is a SWITCH, not an announcement — distinct from the user's `offer` (`contract.wants`, which
# is what the host negotiates against). Nothing outside the home reads it, so a home that writes
# one without reading it has said a word with no listener; a home with no home-manager content to
# gate (a contract-pure home, ADR-0008) writes none at all. The worked example is
# `examples/users/users/duo-a`, which wires `gui` off `hostFacts.granted.gui.enable` — the grant
# reaching home CONTENT is exactly what makes gui `needsOwnHome`, and so a bake.
{ lib }:
{
  cli.enable = lib.mkEnableOption "CLI meta-profile (base tools)";
  gui.enable = lib.mkEnableOption "GUI meta-profile (desktop environment)";
}
