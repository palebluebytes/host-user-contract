# cleo — the privileged-group reference user.
#
# cleo DECLARES `docker` in her identity.extraGroups (see identity.json), but self-declaration can
# never confer a privileged group: the realization CLAMPS it out and restores it ONLY via the
# `containers` grant (ADR-0001 threat model; ADR-0024 for the atomic feature). So on a host that
# grants cleo containers she is in `docker`; on any host that does not, the clamp drops it silently.
# She is also a gui user (gnome), to vary the desktop from ada's plasma across the fleet.
#
# Contract-pure (ADR-0008): only contract wants + request options, and so no
# `custom.home.profiles.*` (see the contract's `home-profiles.nix`). Her gui-ness is her desktop
# request and the host's grant, which is all a portable user needs to say.
{ ... }:
{
  # What cleo ASKS a host for (ADR-0028), declared in her own home rather than in the producer's
  # flake — the producer harvests it as her published offer. `containers` is privileged, so it is
  # never a default: a privileged feature is asked for deliberately or not at all. gui rides the
  # safe-set default, so it needs no line here.
  contract.wants.containers = true;
  contract.requests.gui.desktop = "gnome";
}
