# duo-b — the second half of the SHARED-SETUP pair.
#
# Both of its modes point at the SAME module, and that module's `imports` are byte-identical to the
# ones duo-a's common half uses: that is the whole point. The two users diverge only through the
# identity the builder injects, which is what makes the shared module SHARED CODE rather than one
# user's setup copied onto another. The `shared-code-per-user-data` check proves the pair really
# does differ, and that neither home carries a trace of the other's identity.
#
# What duo-b does NOT have is duo-a's mode-specific content: its whole home is the shared module,
# which is identical in every session. Two modes naming one file is the common case — a user whose
# home does not depend on the session writes it once.
{
  contract.cli = {
    enable = true;
    configuration = ./home.nix;
  };
  contract.gui = {
    enable = true;
    configuration = ./home.nix;
    desktop = "cosmic";
  };
}
