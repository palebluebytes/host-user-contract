# The FEATURE registry — the SINGLE source of truth for the contract's feature vocabulary. One
# entry per feature; every other feature surface the contract exposes (the host's `affordances`
# argument, the account's `granted.*` options, `featureGroups`, the privileged-group clamp list and
# the derived safe set) is a PROJECTION of this map. Adding a feature is a single edit here, and
# the keys can never drift across the projections because there is only one set of keys.
#
# A FEATURE is a POWER a host confers on a PERSON at activation — policy about an account, decided
# per bind. It is deliberately NOT what a MACHINE can run, which is `modes.nix` (ADR-0007). Every
# feature here is PRIVILEGED and has NO PARAMETERS, which is why `safeSet` is empty and a greeter
# confers nothing at all (ADR-0008). A feature never carries a secret (ADR-0003).
#
# Per-entry shape (all fields optional except `grant`):
#   grant            : mkEnableOption description for `contract.users.<u>.granted.<f>`
#   privilegedGroups : groups the grant confers that are SECURITY-CRITICAL. A feature declaring any
#                      is build-time-only — excluded from the safe set, never auto-afforded by the
#                      greeter. `kit.nix` derives the system-wide privileged-group list from these.
#   groups           : NON-PRIVILEGED groups the grant confers. A feature with ONLY these is
#                      runtime-eligible (the safe set), which no entry is today. Session-shaped
#                      groups (a display's input devices) are NOT here: they belong to the MODE
#                      that needs them (`modes.nix`).
#
# EVERY GRANT RIDES THE BIND, over whatever home already exists — so a grant can NEVER change a
# home, and one home serves granted and ungranted alike, for every feature without exception. There
# is no per-feature flag saying otherwise (ADR-0012).
{
  # containers: privileged container-runtime access — the docker/podman groups. Both are
  # root-equivalent (the docker socket runs containers that mount the host fs as root), so this
  # grant is the only way to obtain them. Container access is its own atomic capability, composed
  # with `sudo` (wheel) rather than fused to it, so "containers without sudo" (a hardened build
  # account) is expressible (ADR-0008).
  containers = {
    grant = "container runtime (docker/podman) access for this user (host grant)";
    privilegedGroups = [
      "docker"
      "podman"
    ];
  };

  # sudo: administrative (wheel) access and nothing more — the MINIMAL privileged grant. Each
  # privileged-group feature confers ONE concern's groups (contrast `containers` above, docker/
  # podman), so a host composes them (`sudo` + `containers`) instead of granting one coarse role.
  # wheel is privileged, so like every privileged-group feature it is build-time-only and excluded
  # from the safe set — never afforded by a greeter. A user can never obtain wheel by declaring it
  # in identity; the clamp drops it and only this grant restores it.
  sudo = {
    grant = "wheel/sudo administrative access for this user (host grant)";
    privilegedGroups = [ "wheel" ];
  };

  # virtualization: the privileged disk/libvirtd/qemu-libvirtd groups. Build-time-only, and never
  # afforded at a greeter — running VMs is a power somebody decided you should have, not a property
  # of the machine. (kvm is reserved in kit.nix but not yet conferred by any feature.)
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
  # (so the clamp drops self-declared daemon access), making this build-time-only — a greeter NEVER
  # affords daemon access. A user without this feature is daemon-restricted: they cannot build
  # derivations, install packages, or add store paths beyond what the host placed there when
  # activating their contractPackage.
  nix-daemon = {
    grant = "access to the Nix daemon for this user (host grant)";
    privilegedGroups = [ "nix-users" ];
  };
}
