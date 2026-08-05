# Host-invariant account realization — part of the host↔user contract (ADR-0001,
# mechanic 5). Maps each `custom.users.<u>` to a system account. Powers route
# through *grants*, not raw identity:
#   - the display manager / networkmanager come from the gui grant, not a profile;
#   - **privileged group membership is clamped**: a user's self-declared
#     `identity.extraGroups` is untrusted input, so privileged groups (docker,
#     wheel, …) are filtered out of it and conferred ONLY by a feature grant
#     (contract featureGroups). A user can never escalate by listing `docker` in
#     its own identity; a host must grant `containers` (docker/podman) or `sudo` (wheel).
#
# Audit (ADR-0001 threat model) — which identity fields confer host-side power:
#   name/email/gmail/username .... inert (descriptive)
#   sshKey/trustedKeys ........... login as that user (public keys; the user's call)
#   hashedPassword ............... login credential (one-way hash)
#   extraGroups .................. CLAMPED here — privileged groups need a grant
#   granted.<feature> ............ the host's decision; the only source of privilege
# An account that declares a privileged group (e.g. `wheel`) in its identity does NOT get
# it unless a grant confers it — so a host that wants such an account to keep that power
# MUST grant the matching feature (e.g. `sudo` for wheel, `containers` for docker/podman). The
# host repo's grant matrix is where those decisions live; this module only enforces the rule.
#
# Closes over its contract data (privilegedGroups, featureGroups) rather than reaching
# through the consumer's `self` (ADR-0004): contract/default.nix applies this with the
# registry-derived values, so the shipped module depends on neither `self` nor `inputs`
# — only the NixOS module args. This is what lets the contract become a standalone flake.
{ privilegedGroups, featureGroups }:
{
  lib,
  config,
  ...
}:
let
  users = config.custom.users;
  # Whether any *granted* gui user needs a shared display surface on this host. The contract does
  # NOT decide the session type (wayland vs x11) — that is wholly the SEAT's concern (its display
  # binding and, at a greeter, each desktop's launch command). The contract carries only the grant
  # and the user's free-form desktop NAME (ADR-0021, superseding ADR-0018's session-type derivation).
  guiUsers = lib.filter (u: u.granted.gui.enable or false) (lib.attrValues users);
  anyGuiGranted = guiUsers != [ ];

  grantedNames = u: lib.filter (f: u.granted.${f}.enable or false) (lib.attrNames u.granted);
  # Privileged groups earned from the features granted to this user.
  grantedGroups = u: lib.concatMap (f: featureGroups.${f} or [ ]) (grantedNames u);
  # Self-declared groups with privileged ones clamped out (untrusted input).
  safeDeclared = u: lib.filter (g: !lib.elem g privilegedGroups) u.identity.extraGroups;
in
{
  # Some gui user is granted ⇒ the host needs a shared display surface. Neutral, session-agnostic
  # data: a host-side display binding (SDDM/Plasma, GDM/GNOME, …) reads this and renders whatever
  # session it chooses. The contract is display-server-agnostic (ADR-0021) — it neither knows nor
  # decides wayland vs x11, and offers no desktop→session-type map.
  options.custom.gui.surface.enabled = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Some gui user is granted on this host — a shared display surface is needed (the session type is the seat's choice, ADR-0021).";
  };

  config = {
    custom.gui.surface.enabled = anyGuiGranted;

    # XDG fold (ADR-0025): the residual gui host-glue a seat otherwise hand-writes on every gui
    # user — linking the XDG desktop-portal and applications dirs into the system path so portals
    # and `.desktop` entries resolve. It names no display server or DE, so it is a display-server-
    # agnostic gui host-effect and stays inside ADR-0021's boundary. Set only when some gui user is
    # granted (the gui SURFACE is enabled); a cli-only/headless host never gets it.
    environment.pathsToLink = lib.mkIf anyGuiGranted [
      "/share/xdg-desktop-portal"
      "/share/applications"
    ];

    users.users = lib.mapAttrs (_name: u: {
      isNormalUser = true;
      inherit (u.identity) hashedPassword;
      extraGroups = lib.unique (safeDeclared u ++ grantedGroups u);
      description = u.identity.name;
      openssh.authorizedKeys.keys =
        lib.optional (u.identity.sshKey != "") u.identity.sshKey ++ u.identity.trustedKeys;
    }) users;
  };
}
