# duo-a — the first half of the SHARED-SETUP pair (ADR-0020's "shared code, per-user data"), and
# the roster's one worked example of a HOME-AFFECTING GRANT (issue #55).
#
# duo-a and duo-b exist to prove one thing the other five reference users deliberately do not: that
# an operator CAN enforce a common setup across a set of their own accounts, by importing one shared
# home module and one shared overlay. Since issue #36 that is a permitted variant of the multi-user
# shape rather than an obligation of it — so it gets a live fixture instead of only prose.
#
# What makes duo-a duo-a is its identity.json and its own voice — the desktop it asks for, and the
# content it gates on the grant. The SHARED module it imports is byte-identical to duo-b's, and
# every difference the PAIR is about falls out of `config.identity.username` (see
# `shared/module.nix` and the `shared-code-per-user-data` check); nothing below reaches into it.
#
# duo-a additionally carries the property the whole variant system exists for: its `gui` bake and
# its `base` bake differ in REALIZED HOME CONTENT, not merely in the `granted` field frozen into the
# manifest. That is what `needsOwnBuild` means — a grant that cannot be applied to an already-built
# home — and without one live example the fleet would bake a variant whose content equals base's.
# The `home-affecting-grant-is-load-bearing` check fails if the two bakes ever converge again.
#
# NOT contract-pure (ADR-0008), by design: the shared module and the leaf below set home-manager
# options, so this home needs home-manager to evaluate — the pair is the roster's only
# non-contract-pure member, which is why the gated content lives here rather than being grafted onto
# ada. The conformance tracer borrows ada, never this pair.
{
  config,
  lib,
  hostFacts,
  ...
}:
let
  inherit (config.custom.home) profiles;
in
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

  # ── The WIRE: the host's grant, in the home's own vocabulary ─────────────────────────────────
  # `custom.home.profiles.gui` is the contract's meta-profile vocabulary (`home-profiles.nix`) — a
  # switch this home gates its own content on, and the ONLY thing that makes writing it worth
  # anything. It is wired off `hostFacts.granted`: the producer's per-variant grant, narrowed by
  # `hostFactsFor` to the variant axes, so it reads `false` in the `base` bake and `true` in the
  # `gui` one. `or false` because that narrowing DROPS an ungranted axis rather than setting it
  # false. Same shape the operator's real users repo uses — one wire here, leaf modules gating on
  # the contract's own `cli`/`gui` and on nothing else.
  #
  # Gating CONTENT on a grant is the point; gating the OFFER on it is the circularity
  # `mkContractUser` rejects (the grant is derived FROM the offer), so `contract.wants` stays
  # variant-invariant — this home has no `wants` line at all.
  custom.home.profiles.gui.enable = hostFacts.granted.gui.enable or false;

  # ── The LEAF: real home content, gated on the vocabulary and nothing else ────────────────────
  # A config for the very desktop this home asks for above, materialized ONLY where a host granted
  # gui. This is the difference the `gui` bake exists to carry — a seat that binds duo-a's base
  # variant gets a home with no sway config in it, and no bind-time grant can put one there, which
  # is exactly why gui is `needsOwnBuild` in the feature registry.
  home.file.".config/sway/config" = lib.mkIf profiles.gui.enable {
    text = ''
      # duo-a's sway config — the GUI leaf (custom.home.profiles.gui), present only in the gui bake.
      set $mod Mod4
      bindsym $mod+Shift+q kill
    '';
  };
}
