# Home meta-profile options — part of the host↔user contract (ADR-0001).
# Declared by the home umbrella module as `custom.home.profiles.*`.
# The single home-profile vocabulary: the meta-profiles (cli/gui) a user's home offers.
# Declaring them in one place keeps the vocabulary from scattering; the feature modules
# act on it.
{ lib }:
{
  cli.enable = lib.mkEnableOption "CLI meta-profile (base tools)";
  gui.enable = lib.mkEnableOption "GUI meta-profile (desktop environment)";
}
