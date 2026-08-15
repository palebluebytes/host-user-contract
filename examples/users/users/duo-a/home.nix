# duo-a — the first half of the SHARED-SETUP pair (ADR-0020's "shared code, per-user data").
#
# duo-a and duo-b exist to prove one thing the other five reference users deliberately do not: that
# an operator CAN enforce a common setup across a set of their own accounts, by importing one shared
# home module and one shared overlay. Since issue #36 that is a permitted variant of the multi-user
# shape rather than an obligation of it — so it gets a live fixture instead of only prose.
#
# What makes duo-a duo-a is its identity.json and nothing else: the shared module below is
# byte-identical to duo-b's, and every difference in the built home falls out of
# `config.identity.username` (see `shared/module.nix` and the `shared-code-per-user-data` check).
#
# NOT contract-pure (ADR-0008), by design: the shared module sets home-manager options, so this home
# needs home-manager to evaluate. The conformance tracer borrows ada, never this pair.
{ ... }:
{
  # The shared setup, opted into per user — one module, one overlay, both from `../../shared/`.
  imports = [ ../../shared/module.nix ];

  # A home may declare its OWN overlays even though the producer passes `pkgs` explicitly — this
  # list MERGES with the producer's rather than replacing it. Why that holds, and why this overlay
  # needs no `inputs` specialArg, is spelled out once in `shared/overlay.nix`.
  nixpkgs.overlays = [ (import ../../shared/overlay.nix) ];

  # duo-a asks for nothing privileged, so it declares no `contract.wants` (ADR-0028) and its offer
  # is the safe-set default. Its desktop choice differs from duo-b's only to show that sharing a
  # module costs a user none of its own voice.
  contract.requests.gui.desktop = "sway";
  custom.home.profiles.gui.enable = true;
}
