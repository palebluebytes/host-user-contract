# The FEATURE registry — the SINGLE source of truth for the contract's feature vocabulary. One
# entry per feature; every other feature surface the contract exposes (the host's `affordances`
# argument, the account's `granted.*` options, `featureGroups`, the privileged-group clamp list and
# the derived safe set) is a PROJECTION of this map. Adding a feature is a single edit here, and
# the keys can never drift across the projections because there is only one set of keys.
#
# A FEATURE is a POWER a host confers on a PERSON at activation — policy about an account, decided
# per bind. It is deliberately NOT the other kind of thing a host has to say: whether this MACHINE
# can run a graphical session is a capability of the box, not a judgement about anybody, and it is
# declared once as `contract.modes` (see `modes.nix`). Collapsing the two put a machine capability
# in a per-user policy namespace, where it behaved unlike every other entry here.
#
# EVERY FEATURE IN THIS REGISTRY IS PRIVILEGED, and that is a property worth reading off the file
# rather than a coincidence: with the display capability gone, what is left is exactly the set of
# powers that need a deliberate, per-person decision. It is why `safeSet` — the features a greeter
# may confer on a stranger — is currently EMPTY, and why a greeter grants nothing at all.
#
# The contract handles NO secrets beyond the login credential: a feature never pulls a
# secret onto a host and the contract never re-keys or owns user key material (a user's
# own home secrets ride the user's own key, provisioned by the user's own home module).
#
# Per-entry shape (all fields optional except `grant`):
#   grant            : mkEnableOption description for `contract.users.<u>.granted.<f>`
#   privilegedGroups : groups the grant confers that are SECURITY-CRITICAL — a user can
#                      never self-escalate into these by declaring them in identity.extraGroups;
#                      the realization clamps them out and only restores them via a grant.
#                      A feature with any privilegedGroups is build-time-only (excluded from
#                      the safe set and never auto-afforded by the greeter). kit.nix derives
#                      the system-wide `privilegedGroups` clamp list from these.
#   groups           : NON-PRIVILEGED groups the grant confers — self-declaration in
#                      identity.extraGroups is safe, but the grant is still the canonical path. A
#                      feature with ONLY these is runtime-eligible (the safe set), which no entry
#                      is today. Session-shaped groups (a display's input devices) are NOT here:
#                      they belong to the MODE that needs them (`modes.nix`).
#
# A feature has NO PARAMETERS. It is a bare capability — a set of groups a host confers — and the
# one parameter the contract ever carried (`gui.desktop`) turned out to describe a SESSION rather
# than a capability, so it lives on the gui MODE (`modes.nix`) where the thing it parameterises is.
# That is why `contract.users.<u>` carries only an identity, a grant set and the mode it was bound
# in: there is nothing else about
# a feature for a bind to bridge.
#
# EVERY GRANT RIDES THE BIND. A grant is a host-side effect conferred on the ACCOUNT at activation,
# over whatever home already exists — so a grant can NEVER change a home, and one home serves
# granted and ungranted alike, for every feature without exception. There is no per-feature flag
# saying otherwise. What CANNOT be conferred at activation is home CONTENT, which cannot be
# injected into a sealed derivation; that is a MODE, and homes are keyed by mode rather than by a
# combination of grants.
{
  # containers: privileged container-runtime access — the docker/podman groups. Both are
  # root-equivalent (the docker socket runs containers that mount the host fs as root), so a user
  # can never obtain them by declaring them in identity.extraGroups; only this grant does. Container
  # access is its own atomic capability, composed with `sudo` (wheel) rather than fused to it, so
  # "containers without sudo" (a hardened build account) is expressible.
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
