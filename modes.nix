# The MODE registry — the SINGLE source of truth for the contract's MODE vocabulary, and the
# backbone of BOTH machine-facing surfaces: what a user declares they run in, and what a host
# declares it can run. Adding a mode is a single edit here; every other mode surface (a user's
# `contract.<mode>` options, a host's `contract.modes` enum, the per-system home matrix's axis
# names, the key a home is published under) is a PROJECTION of this map.
#
# A MODE is the SESSION SHAPE a home is BUILT FOR — and, on the host side, a CAPABILITY OF THE
# MACHINE. Those are the same vocabulary because they are the same question asked from two ends:
# "can this box run a graphical session?" and "was this home built for one?" A host that cannot run
# a shape simply does not offer it, which is incapacity rather than policy — and that is exactly
# what distinguishes a mode from a FEATURE (`features.nix`), which is a power somebody decided a
# particular person should have.
#
# THE TWO REGISTRIES TOUCH NOWHERE. A mode used to name the feature a host afforded in order to run
# it, which meant a machine capability had to be laundered through a per-user policy namespace; the
# host now declares its modes directly, so there is no association left to keep in step.
#
# Modes are MUTUALLY EXCLUSIVE — a home is built for exactly one — which is why N modes yield at
# most N homes per user rather than 2ⁿ, and why `homes` is keyed by a mode NAME rather than a set.
#
# Per-entry shape:
#   description : what this session shape IS, in the user's own vocabulary. It is the description
#                 of the user's `contract.<mode>.enable` option, so the word a user reads when
#                 declaring a mode and the word the contract uses for it are one string.
#   floor       : OPTIONAL, default false. This mode is the FLOOR — the one every host runs, that
#                 every selection falls back to, and that no host has to declare. EXACTLY ONE mode
#                 carries it; zero or two is a named error (`floorOf` in lib.nix), because a
#                 selection with no floor has no fallback and one with two has no answer.
#   groups      : OPTIONAL. Groups an account needs IN ORDER TO RUN this session shape. They ride
#                 the SELECTED MODE, not a grant: a graphical session needs its input devices by
#                 virtue of being graphical, and nobody should have to decide that per person.
#                 Non-privileged by construction — a mode is a capability, never a power, so a
#                 privileged group here would be an escalation the clamp exists to stop.
#   display     : OPTIONAL, default false. Running this mode needs a shared DISPLAY SURFACE on the
#                 host. A registry FLAG rather than a literal in the realization, for the same
#                 reason `floor` is one: a mode name inside the derivation would make this map
#                 decorative and a third mode a code change.
#   options     : OPTIONAL. The mode's own PARAMETERS, merged into `contract.<mode>` beside
#                 `enable` and `configuration`. Parameters live on the thing they parameterise: a
#                 desktop NAME is a property of the graphical session, not of the account.
{ lib }:
{
  # cli: a terminal-only session. THE FLOOR — every host runs it, nobody declares it, and a user
  # enabling it can be bound anywhere. It needs no groups (a terminal has no devices to reach) and
  # no display, and takes no parameters (a terminal has nothing to choose). That it needs nothing
  # at all is exactly what makes it the floor.
  cli = {
    description = "the CLI mode — a terminal-only session";
    floor = true;
  };

  # gui: a graphical desktop session. A host declares `contract.modes = [ "gui" ]` when it has a
  # display; everything below then follows for every user bound there in this mode, with no
  # per-person decision to make.
  #
  # What makes gui a MODE rather than a power is the half of it that cannot be conferred at
  # activation: a desktop's dotfiles and session config are home CONTENT, and content cannot be
  # injected into a sealed derivation. The half that CAN be conferred — the input devices below —
  # rides the mode too, because needing them is a property of running a graphical session rather
  # than a judgement about who is running it.
  gui = {
    description = "the GUI mode — a graphical desktop session";
    # The input devices a graphical session drives. All non-privileged: self-declaring them in
    # identity.extraGroups would be safe, and the clamp leaves them alone.
    groups = [
      "input"
      "uinput"
      "plugdev"
      "dialout"
    ];
    # A graphical session needs a shared display surface. The realization turns
    # `contract.display.enabled` on for any host that runs a mode carrying this, so the host's own
    # display binding (SDDM/Plasma, GDM/GNOME, a greeter's launcher) has one neutral flag to read.
    # The contract names no display server and no session type — wayland vs x11 is wholly the
    # seat's concern.
    display = true;
    options = {
      # Which DESKTOP this user logs into. FREE-FORM and DE-agnostic by design: the contract
      # carries the user's opaque preference so it travels with the home — the same desktop on any
      # seat that offers it, which is the portable-user north star — and the SEAT maps the name to
      # a real DE and its launch (`contract.greeter.desktops`). An un-offered or empty name
      # degrades to the seat default. It NEVER names a system package.
      #
      # Its only consumer is `~/.contract-desktop`, which the contract writes into the gui home so
      # the greeter's launcher can read the choice BEFORE evaluating any of the home's Nix.
      desktop = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Desktop this user logs into; a free-form name the seat maps to an offered desktop and its launch. Empty ⇒ the seat default. The session type is the seat's concern, not the contract's.";
      };
    };
  };

  # A third mode would go here. `mobile` is the shape one takes: its own `groups`, its own
  # `display`, not the floor, and incomparable with `gui` — a phone runs { cli, mobile } and a
  # desktop runs { cli, gui }, and no host ever needs them ordered against each other. That is why
  # the registry carries a floor FLAG rather than a total rank, and why two rich modes at one bind
  # is a refusal rather than an invented tie-break.
}
