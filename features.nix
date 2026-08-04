# The feature registry — the SINGLE source of truth for the contract's feature
# vocabulary (ADR-0001, mechanic 2). One entry per feature; every other feature
# surface the contract exposes (the `granted.*` grant options, `featureGroups`, the
# user-owned `featureConfig` options, the imported feature modules, and the derived
# safe set) is a PROJECTION of this map — see contract/default.nix. Adding a feature
# is a single edit here, and the keys can never drift across the projections because
# there is only one set of keys.
#
# The contract handles NO secrets beyond the login credential: a feature never pulls a
# secret onto a host and the contract never re-keys or owns user key material (a user's
# own home secrets ride the user's own key, provisioned by the user's own home module).
#
# Per-entry shape (all fields optional except `grant`):
#   grant            : mkEnableOption description for `custom.users.<u>.granted.<f>`
#   privilegedGroups : groups the grant confers that are SECURITY-CRITICAL — a user can
#                      never self-escalate into these by declaring them in identity.extraGroups;
#                      the realization clamps them out and only restores them via a grant.
#                      A feature with any privilegedGroups is build-time-only (excluded from
#                      the safe set and never auto-granted by the greeter). kit.nix derives
#                      the system-wide `privilegedGroups` clamp list from these.
#   groups           : NON-PRIVILEGED groups the grant confers — self-declaration in
#                      identity.extraGroups is safe, but the grant is still the canonical
#                      path. Features with only these may be runtime-eligible (safe set).
#   config           : user-owned option fragment merged into `custom.users.<u>` — the
#                      feature's *parameters* (host-affecting ones aggregate, ADR-0003).
{ lib }:
{
  # gui: desktop environment. Its host effects are two contract-neutral things only —
  # the display-surface-needed flag (realization → custom.gui.surface.enabled) and the
  # non-privileged input groups below. Everything device/package/layout-specific (uinput,
  # keyboard layout, app permits, the display backend AND the session type) is a HOST
  # binding (gui-desktop.nix + the user's glue), so the contract has no gui *module* and is
  # display-server-agnostic (ADR-0021). In the safe set: no secret, no privileged group.
  gui = {
    grant = "the GUI feature for this user (host grant)";
    groups = [
      "input"
      "uinput"
      "plugdev"
      "dialout"
    ];
    config = {
      # gui.desktop: which DESKTOP this user logs into (ADR-0013). FREE-FORM and DE-agnostic by
      # design — the contract carries the user's opaque preference (so it travels with the home:
      # same desktop on any seat that offers it, the portable-user north star); the SEAT maps the
      # name to a real DE and its launch (custom.greeter.desktops at a greeter), and an
      # un-offered/empty name degrades to the seat default. NEVER names a system package. The
      # session type (wayland/x11) is NOT a contract concern at all — the seat's launch owns it
      # (ADR-0021); the contract carries only the desktop NAME.
      gui.desktop = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Desktop this user logs into; a free-form name the seat maps to an offered desktop and its launch (ADR-0013). Empty ⇒ the seat default. Session type is the seat's concern, not the contract's (ADR-0021).";
      };
    };
  };

  # workstation: privileged host access — the docker/podman/wheel groups. A user can
  # never obtain these by declaring them in identity.extraGroups; only this grant does.
  workstation = {
    grant = "privileged workstation groups for this user (host grant)";
    privilegedGroups = [
      "docker"
      "podman"
      "wheel"
    ];
  };

  # sudo: administrative (wheel) access and nothing more — the MINIMAL privileged grant.
  # workstation also confers docker/podman; this is for accounts that need sudo without a
  # dev toolchain (e.g. a break-glass admin, or a co-admin user). wheel is privileged, so
  # like workstation it is build-time-only and excluded from the safe set — never a
  # greeter auto-grant. A user can never obtain wheel by declaring it in identity; the
  # clamp drops it (ADR-0001 threat model) and only this grant restores it.
  sudo = {
    grant = "wheel/sudo administrative access for this user (host grant)";
    privilegedGroups = [ "wheel" ];
  };

  # virtualization: the privileged disk/libvirtd/qemu-libvirtd groups, split out of gui
  # (slice 11) so gui stays in the safe set — these are build-time-only, never auto-
  # granted at a greeter. (kvm is reserved in kit.nix but not yet conferred by any feature.)
  virtualization = {
    grant = "privileged virtualization groups for this user (host grant)";
    privilegedGroups = [
      "disk"
      "qemu-libvirtd"
      "libvirtd"
    ];
  };

  # nix-daemon: access to the Nix daemon socket for this user. Confers `nix-users` group
  # membership — the host wires `nix.settings.allowed-users = ["@nix-users"]` so only
  # members of this group may talk to the daemon. `nix-users` is in `privilegedGroups`
  # (so the clamp drops self-declared daemon access), making this build-time-only — the
  # greeter NEVER auto-grants daemon access (ADR-0017). A user denied this feature is
  # daemon-restricted: they cannot build derivations, install packages, or add store paths
  # beyond what the host placed there when activating their contractPackage.
  nix-daemon = {
    grant = "access to the Nix daemon for this user (host grant)";
    privilegedGroups = [ "nix-users" ];
  };
}
