# Host-invariant account realization. Maps each `contract.users.<u>` to a system account, and
# derives the one neutral display fact a host's own display binding reads.
#
# Powers route through GRANTS, never raw identity (ADR-0006): an identity cannot name a group at
# all, so this module has no untrusted-input story to tell and no self-escalation route to close.
#
# It is the BUILD-TIME ADAPTER over the shared account plan: it owns no identity→account field
# logic itself — `accountPlan { identity, grants, mode }` derives every account field — and only
# maps that neutral record into the NixOS `users.users` shape. The runtime adapter (the greeter's
# `provision`) renders the SAME plan, so the two cannot drift (ADR-0020).
#
# It closes over its contract data (the injected `accountPlan`, the mode registry and the run-set
# derivation) rather than reaching through a consumer's `self` (ADR-0002).
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
  # registry's own flag rather than by naming `gui` (ADR-0009).
  needsDisplay = lib.any (m: modeRegistry.${m}.display or false) runs;
in
{
  # A host that runs a display mode needs a shared display surface: neutral, session-agnostic data
  # a host-side display binding reads and renders whatever session it chooses (ADR-0021). It
  # follows the MACHINE, not its users, so a seat has one before anybody is bound to it — which is
  # what a greeter needs (ADR-0009).
  #
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
