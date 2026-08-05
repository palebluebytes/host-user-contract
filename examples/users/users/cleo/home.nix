# cleo — the privileged-group reference user.
#
# cleo DECLARES `docker` in her identity.extraGroups (see identity.json), but self-declaration can
# never confer a privileged group: the realization CLAMPS it out and restores it ONLY via the
# `containers` grant (ADR-0001 threat model; ADR-0024 for the atomic feature). So on a host that
# grants cleo containers she is in `docker`; on any host that does not, the clamp drops it silently.
# She is also a gui user (gnome), to vary the desktop from ada's plasma across the fleet.
#
# Contract-pure (ADR-0008): only contract/home-profile + request options.
{ ... }:
{
  contract.requests.gui.desktop = "gnome";
  custom.home.profiles.gui.enable = true;
}
