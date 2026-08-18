# The MODE registry — the SINGLE source of truth for the contract's MODE vocabulary
# (ADR-0032). It follows the pattern `features.nix` sets: one entry per mode, and every other
# mode surface the contract exposes (the user's `contract.supports` options, the home's
# `custom.home.profiles.*` switches, the floor, the host's derived `runs` set, and the per-system
# matrix's axis names) is a PROJECTION of this map — see kit.nix and lib.nix. Adding a mode is a
# single edit here, and the keys can never drift across the projections because there is only one
# set of keys.
#
# A MODE is the SESSION SHAPE a home is BUILT FOR. It is the other half of the split ADR-0032
# made: a GRANT is a host-side effect conferred at activation on whatever home already exists and
# can never change a home; a MODE is what the home was built as, and no bind can change it.
#
# Modes are MUTUALLY EXCLUSIVE — a home is built for exactly one — which is the whole economic
# difference from the grant powerset this replaced: N modes yield at most N homes per user, not
# 2ⁿ. That is why there is no combination anywhere in the projections, and why `homes` is keyed by
# a mode NAME rather than by a set of them.
#
# Per-entry shape:
#   description : what this session shape IS, in the user's own vocabulary. It is the description
#                 of BOTH derived options — `contract.supports.<mode>` (the user saying it can run
#                 here) and `custom.home.profiles.<mode>.enable` (the home gating its content) —
#                 so the two can never describe the same word differently.
#   grant       : OPTIONAL. The FEATURE whose grant is associated with this mode. A host that
#                 affords that feature RUNS this mode (`runs` is derived from the affordances, so
#                 no host declares a mode). The association is one-way and does NOT make the mode
#                 imply the grant: a host must still be able to confer gui's input groups to a
#                 cli-mode user, and `wants.gui` stays independently vetoable (ADR-0032's rejected
#                 "make the mode imply the grant"). Omitted for the floor, which every host runs.
#   floor       : OPTIONAL, default false. This mode is the FLOOR — the one every host runs and
#                 every selection falls back to. EXACTLY ONE mode carries it; zero or two is a
#                 named error (`floorOf` in lib.nix), because a selection with no floor has no
#                 fallback and one with two has no answer.
#
# Free-form mode names are deliberately NOT possible (ADR-0032, rejected on ADR-0028's precedent):
# `contract.supports` is fully typed off these keys, so a typo'd mode is an eval error in the
# user's own repo rather than a user nothing can bind, discovered by a host operator.
{
  # cli: a terminal-only session. THE FLOOR — every host runs it, nobody declares it, and a user
  # supporting it can be bound anywhere. It carries NO associated grant: there is no feature a
  # host affords in order to run a terminal, which is exactly what makes it the floor.
  cli = {
    description = "the CLI mode — a terminal-only session";
    floor = true;
  };

  # gui: a graphical desktop session. Associated with the `gui` feature, so a host affording gui
  # runs this mode and a headless one does not. What makes gui a MODE rather than only a grant is
  # the half of it that cannot be conferred at activation: a desktop's dotfiles and session config
  # are home CONTENT, and content cannot be injected into a sealed derivation. The other half —
  # the input groups and the display-surface flag — is the grant, and it still rides the bind
  # (features.nix).
  gui = {
    description = "the GUI mode — a graphical desktop session";
    grant = "gui";
  };

  # A third mode would go here. `mobile` is the shape one takes: its own grant, not the floor, and
  # incomparable with `gui` — a phone runs { cli, mobile } and a desktop runs { cli, gui }, and no
  # host ever needs them ordered against each other. That is why the registry carries a floor FLAG
  # rather than a total rank (ADR-0032, rejected options).
}
