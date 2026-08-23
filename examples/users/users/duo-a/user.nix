# duo-a — the first half of the SHARED-SETUP pair, and the members' one worked example of
# MODE-SPECIFIC HOME CONTENT.
#
# duo-a and duo-b exist to prove one thing the other five reference users deliberately do not: that
# an operator CAN enforce a common setup across a set of their own accounts, by importing one
# shared home module and one shared overlay. That is a permitted arrangement rather than an
# obligation, so it gets a live fixture instead of only prose.
#
# duo-a additionally carries the property the whole per-mode system exists for: its `gui` home and
# its `cli` home differ in REALIZED CONTENT. Each mode points at its OWN module, and the two
# SUBSTITUTE for one another — a graphical window-manager config beside its terminal counterpart —
# which is exactly what no bind-time grant could ever do, since content cannot be injected into a
# sealed derivation. That is what makes a MODE a mode and not a grant.
#
# duo-a is the pair `mode-substitution-is-load-bearing` finds. It is the ONLY member here
# whose modes substitute content — ada, cleo, duo-b and admin each run two modes off one
# home's worth of content, which is legitimate and not what that check refuses (ADR-0027) —
# so the fleet-wide claim rests on this user, and fails the moment these two homes converge.
#
# The content shared between the two modes lives in `./common.nix`, which both import. There is no
# per-mode conditional anywhere: a module that belongs in both homes is imported by both, and a
# module that belongs in one is named by one.
{
  contract.cli = {
    enable = true;
    configuration = ./cli.nix;
  };
  contract.gui = {
    enable = true;
    configuration = ./gui.nix;
    # A different desktop from duo-b's, because sharing a module costs a user none of its own voice.
    desktop = "sway";
  };
}
