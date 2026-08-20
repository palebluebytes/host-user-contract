# Host-invariant account realization. Maps each `contract.users.<u>` to a system account, and
# derives the one neutral display fact a host's own display binding reads.
#
# Powers route through GRANTS, never raw identity. An identity cannot name a group at all, so
# there is no self-escalation route to close: an account's groups are what its SESSION needs
# (`modes.<m>.groups`) plus what the host AFFORDED, and both are decisions somebody else made.
#
# Audit — which identity fields confer host-side power:
#   name/email/gmail/username .... inert (descriptive)
#   sshKey/trustedKeys ........... login as that user (public keys; the user's call)
#   hashedPassword ............... login credential (one-way hash)
#   granted.<feature> ............ the host's decision; the only source of privilege
#
# This module is the BUILD-TIME ADAPTER over the shared account plan: it owns no identity→account
# field logic itself — `accountPlan { identity, grants, mode }` derives every account field — and
# only maps that neutral record into the NixOS `users.users` shape. The runtime adapter (the
# greeter's `provision`) renders the SAME plan, so the two cannot drift.
#
# It closes over its contract data (the injected `accountPlan`, the mode registry and the run-set
# derivation) rather than reaching through a consumer's `self`, which is what lets the contract be
# a standalone flake.
{
  accountPlan,
  modeRegistry,
  runsWith,
}:
{
  lib,
  config,
  ...
}:
let
  users = config.contract.users;
  # The modes this MACHINE runs: the floor, plus whatever it declared. Read here for the display
  # decision alone — which account gets which session is the bind's business, not this module's.
  runs = runsWith config.contract.modes;
  # Does any session shape this host runs need a shared display surface? Read off the mode
  # registry's own flag rather than by naming `gui`, so a third mode that needs a display says so
  # in one place and this derivation never changes.
  needsDisplay = lib.any (m: modeRegistry.${m}.display or false) runs;
in
{
  # A host that runs a display mode needs a shared display surface. Neutral, session-agnostic
  # data: a host-side display binding (SDDM/Plasma, GDM/GNOME, a greeter's launcher) reads this
  # and renders whatever session it chooses. The contract is display-server-agnostic — it neither
  # knows nor decides wayland vs x11, and offers no desktop→session-type map.
  #
  # It follows the MACHINE, not its users. A seat with a display has one whether or not anybody is
  # bound to it yet, which is what a greeter needs: the surface must exist before the first
  # walk-up user does.
  # Read-only, and the DERIVATION is the default: a host reads this, it never writes it. (A
  # `readOnly` option may be defined at most once, so the value has to arrive as the default
  # rather than as a `config` assignment beside it.)
  options.contract.display.enabled = lib.mkOption {
    type = lib.types.bool;
    readOnly = true;
    default = needsDisplay;
    description = "This host runs a session shape that needs a shared display surface (derived from `contract.modes`). The session type is the seat's choice, not the contract's.";
  };

  config = {
    # The residual gui host-glue a seat otherwise hand-writes: linking the XDG desktop-portal and
    # applications dirs into the system path so portals and `.desktop` entries resolve. It names
    # no display server and no DE, so it stays inside the display-server-agnostic boundary. Set
    # only where a display surface exists; a headless host never gets it.
    environment.pathsToLink = lib.mkIf needsDisplay [
      "/share/xdg-desktop-portal"
      "/share/applications"
    ];

    # Map each user's account plan into the NixOS `users.users` shape. All identity→account field
    # derivation lives in `accountPlan`; this adapter only supplies the module-specific framing
    # (`isNormalUser`, the `openssh.authorizedKeys.keys` nesting) around the neutral record.
    users.users = lib.mapAttrs (
      _name: u:
      let
        plan = accountPlan {
          inherit (u) identity mode;
          grants = u.granted;
        };
      in
      {
        isNormalUser = true;
        inherit (plan) hashedPassword description extraGroups;
        openssh.authorizedKeys.keys = plan.authorizedKeys;
      }
    ) users;
  };
}
