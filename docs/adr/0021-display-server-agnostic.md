# The contract is display-server agnostic; the seat offers desktops

**Status:** Accepted (2026-08-20). Bounds what the gui mode of
[0007](0007-two-registries.md) may carry.

The contract once knew about display servers. It carried a `wayland`/`x11` enum in its schema,
unioned every graphical user's choice into a host-wide surface, and derived a session type in its
launcher.

That went wrong twice over.

**Session type is not a portable property of a person.** Nobody has an independent preference about
a protocol — it is a property of the desktop they chose. And a desktop's launch command already
fully determines it: `startplasma-wayland` *is* a wayland session, and a command that needs an
environment variable sets it itself.

**It is not a cross-user quantity either.** The union existed to stop two people fighting over a
host singleton, which was an artifact of users writing raw host options in the first place.

## Decision

**The contract carries a free-form desktop NAME and a neutral display flag. It never names, derives,
or decides wayland versus x11.**

- **The user carries the choice**: `contract.gui.desktop = "plasma"` — free-form, so the contract is
  DE-agnostic. It travels with the identity and yields the same desktop on every seat that offers
  it, which is the portable-user north star. An un-offered or empty name **degrades to the seat
  default**, never breaks the login.
- **The seat offers desktops**: `contract.greeter.desktops.<name>.command`, plus a default. The
  operator enables the desktop environments the seat provides and binds each one's session-entry
  command — exactly what a display manager launches. The command is **self-contained**: it sets its
  own session environment if it needs one.
- **The host gets one neutral flag.** `contract.display.enabled` says *this machine runs a session
  shape that needs a shared display surface* ([0009](0009-host-declares-modes.md)). What the host
  brings up in response is entirely its own.

## The choice travels in the binding index, not in the home

A desktop name is a **parameter of a mode**, which makes it a fact about the *user* — so it is
published where every other fact about a user is published: the binding index,
`contractUsers.<system>.<user>.modeParams.<mode>`
([0011](0011-prebuilt-binding-mode.md)). A reader that has selected a mode looks that mode's
parameters up and finds them, having built nothing and opened nothing.

`modeParams` is a **projection of the mode registry's own `options`**, exactly as the user's
declaration schema is ([0010](0010-user-declares-session-shapes.md)). A mode that gains a parameter
publishes it with no edit in the producer and none in any consumer; a mode that declares none — the
`cli` floor — publishes an empty set, so the mechanism costs a terminal user nothing.

The **session launcher takes the desktop as an argument**, from whoever selected the mode it
parameterises. On the greeter path the orchestrator reads it in the same restricted-eval `nix eval`
that reads the user's published modes, one step after selection. An empty or omitted value is the
ordinary case and degrades to the seat default, so a caller with nothing to pass passes nothing.

**This was a file, and the file was the mistake.** The contract used to write
`~/.contract-desktop` into every gui home, on the reasoning that a launcher cannot evaluate Nix. The
launcher indeed cannot — but the orchestrator that invokes it already evaluates twice before
reaching it, so the premise never bound. What the file did buy was a real cost: it made the contract
the author of home CONTENT, and every judgement about whether a *mode* substituted content then had
to set the contract's own output aside first ([0027](0027-mode-need-not-change-home-content.md)).
Publishing the value as data removes the writer and the subtraction together, and leaves the rule
that **the contract composes no content into a home** true without qualification.

A host on the declarative path is better served too: it reads the parameter at eval time, where it
can wire its own display manager with it, rather than needing a runtime hook to read a dotfile.

## Full desktops work, and one launch detail is worth recording

Both GNOME and Plasma are brought up live under the greeter in VM checks. A self-contained session
entry like Plasma's works as a direct command; GNOME's `gnome-session` starts its shell as a
*systemd user service* detached from the login session, so the compositor cannot find its seat. That
seat's binding therefore launches the shell as a **direct child** of the greeter's session.

**That detail lives in the host's binding, not in the contract** — which is the boundary working:
the contract decided nothing about it, and the seat that owns the desktop owns its launch.

Window managers need no special case. They are `desktops` entries with nothing unusual about them.

## Consequences

- **A consuming host's display binding is unconditional** about its display server. There is no
  branch for the contract to feed.
- **Adding a desktop is a host edit**, never a contract release.
- **The gui mode's registry entry carries no protocol** — only the input groups a graphical session
  needs, a display flag, and the free-form name.
- **The contract composes no content into a home**, without qualification. `~/.contract-desktop` was
  the only exception and it is gone.

## Considered alternatives

- **A contract-side desktop enum** — rejected: the contract would have to know every desktop
  environment and cut a release to add one.
- **Derive the session type from the desktop, contract-side** — rejected: still makes the contract
  encode display policy, and the derivation is redundant because the launch command already
  determines it.
- **Offer a protocol hint the seat may ignore** — rejected: any such vocabulary in the contract is
  the leakage being removed.
- **Leave it, since the fleet is single-protocol anyway** — rejected: the mechanism was live in the
  schema, the conformance suite and the greeter, and it broke a real host on a contract bump.
- **Put the desktop choice in the identity** — rejected: a desktop is *experience*, not identity. It
  belongs with the session shape it parameterizes, so it travels as that mode's own parameter rather
  than as part of the credential.
- **Write it into the home as `~/.contract-desktop`** — *was* the decision; reversed above. Its
  premise (a launcher cannot evaluate, so the value must be a file) does not hold — the orchestrator
  that invokes the launcher evaluates twice before reaching it — and it made the contract the author
  of home content, which cost [0027](0027-mode-need-not-change-home-content.md) a standing
  subtraction rule. The one property it genuinely had, *any launcher can read it with no Nix at
  all*, went unused: this repo's own declarative display binding sets its default session host-side
  and never consulted the file.
- **Thread the desktop from the greeter to the launcher as an argument and publish nothing** —
  rejected, and it is the tempting half-move. It fixes the home-content problem while leaving the
  value reachable only by something that has already evaluated the user's flake, so a declarative
  host has no route to it at all — strictly worse than the file, which at least existed. The
  argument is how the launcher *receives* it; the index is how it is *published*, and both are
  needed.
