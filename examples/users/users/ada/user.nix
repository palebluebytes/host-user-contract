# ada — the multi-machine (portable) reference user, and this repo's PORTABLE-USER NORTH STAR.
#
# ONE identity that logs in as a GUI user on a seat host and a CLI-only user on a headless one.
# Which session she gets is decided by each HOST — a seat declares that it runs the gui mode, a
# headless box declares nothing and runs the floor — and ada says nothing per-host at all. She
# simply declares that she runs in both, and names the desktop she likes; the seat maps that name
# to a real DE, or falls back to its own default if it does not offer it.
#
# This is also the shape a walk-up greeter login takes: a seat running the greeter runs whatever
# modes the MACHINE declared, so it selects `gui` for any stranger with a flake URL who publishes
# one, and brings up plasma. Nothing is granted to make that happen — the safe set is empty — and
# nothing about that path is declared here or on the seat.
#
# ada's `identity.json` is the members' ONE documented FULL FORM — every field the contract's
# identity schema knows, spelled out, because the schema is worth seeing written down once. Only
# `name`, `email` and `username` are REQUIRED; the other six users omit whatever nothing reads for
# them. Note what an identity does NOT carry: any notion of what this account may DO. It is a
# person, not their powers.
{
  # BOTH session shapes. Neither carries a `configuration`: ada's home content is whatever the
  # contract's own baseline gives her, which is a real shape for a reference user and keeps this
  # file about the one thing it is here to teach. A mode with no configuration still yields an
  # account and a home.
  contract.cli.enable = true;
  contract.gui = {
    enable = true;
    # A free-form, DE-agnostic name that travels with the user. It is inert until a host runs the
    # gui mode; then the seat maps it to a real desktop, or to its own default.
    desktop = "plasma";
  };
}
