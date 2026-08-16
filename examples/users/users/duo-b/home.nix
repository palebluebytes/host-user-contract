# duo-b — the second half of the SHARED-SETUP pair (ADR-0020's "shared code, per-user data").
#
# Its `imports` and `nixpkgs.overlays` lines are byte-identical to duo-a's: that is the whole point.
# The two homes diverge only through the identity the binding injects, which is what makes the
# shared module SHARED CODE rather than one user's setup copied onto another. The
# `shared-code-per-user-data` check proves the pair really does differ, and that neither home
# carries a trace of the other's identity.
#
# NOT contract-pure (ADR-0008), like duo-a and for the same reason.
{ ... }:
{
  imports = [ ../../shared/module.nix ];

  nixpkgs.overlays = [ (import ../../shared/overlay.nix) ];

  # Same story as duo-a: no `contract.wants` line, so the safe-set default is the whole offer
  # (ADR-0028); a different desktop, because sharing a module costs a user none of its own voice.
  contract.requests.gui.desktop = "cosmic";

  # No `custom.home.profiles.*` line either: duo-b gates nothing on the grant — its whole content
  # comes from the shared module, which is identical in every bake. The grant wire and the content
  # it gates are duo-a's story (issue #55); what duo-b proves is the shared-code half, unchanged.
}
