# A host declares the modes the machine runs; affordances ride each bind

**Status:** Accepted (2026-08-20). The host-side half of [0007](0007-two-registries.md).

A host says two different kinds of thing, and keeping them apart is the payload of the whole design:

```nix
{
  contract.modes = [ "gui" ];                    # WHAT THIS MACHINE IS

  imports = [ (contract.lib.bindContractUsers {  # WHAT EACH PERSON MAY DO
    source = users;
    users = { ada = { }; cleo.containers = true; admin.sudo = true; };
  }) ];
}
```

`contract.modes` is a fact about the hardware, stated once, true for everybody, giving nobody
anything. Each entry in `users` is a decision about a person, and it sits beside the person it is
about. `ada = { }` — afforded nothing — still logs into a full desktop, because a graphical session
is what the machine runs and the gui mode carries its own input groups.

## The declaration is fail-closed, typed, and a set

- **Fail-closed**: `contract.modes` defaults to `[ ]`. A machine runs nothing rich until it says so.
- **Typed against the registry**: `listOf (enum modeNames)`, so a misspelled mode is an error where
  it is written.
- **The floor is implicit**: no host declares that it runs a terminal.

The run-set derivation **filters the registry** rather than appending to a list:

```nix
runsWith = declared: lib.filter (m: m == floorMode || lib.elem m declared) modeNames;
```

That makes `contract.modes` a genuine **set**: order washes out, duplicates wash out, a redundantly
spelled floor washes out, and no spelling can *exclude* the floor. A concatenation would have made
all four expressible and three of them wrong.

## The display surface is derived forwards

It used to be derived backwards: *some account was afforded gui, therefore this machine must have a
screen.* An account's policy standing in for a machine's hardware — and it meant a host with no
display could claim one by conferring a power.

```nix
needsDisplay = lib.any (m: modeRegistry.${m}.display or false) runs;
```

Read off the registry's own flag rather than by spelling `gui` inside a derivation, so a third mode
that needs a display says so in one place and this line never changes. The host's own display
binding — SDDM, GDM, a greeter's launcher — reads one neutral flag, `contract.display.enabled`,
which is `readOnly`: it is a derivation, not a knob.

## Why the two are not one namespace

A single host-side namespace was tried in both directions and both are wrong:

- **Modes derived from affordances** (a host affords `gui`, therefore it runs the gui mode) — this
  is the fusion [0007](0007-two-registries.md) exists to remove. It makes a machine's capability a
  side effect of a judgement about a person, and it cannot express a headless host that confers
  input-device groups for a plugged-in peripheral.
- **Two host-side declarations that must agree** — rejected wherever it appears in this design: two
  statements with nothing forcing them into agreement is a drift waiting to happen.

What resolves it is that they are declarations about **different subjects**. A machine capability is
per-host and stated once. A power is per-person and stated per bind. There is nothing to reconcile,
because they never describe the same thing.

## Consequences

- **Per-user differentiation lives where it belongs**, at the bind, and needs no second mechanism:
  two people on one machine, two affordance sets, two accounts, one capability statement.
- **A greeter needs no entry for anybody.** It confers the safe set — empty — and runs the modes the
  machine declared, so a stranger gets a desktop and can never get wheel.
- **`contract.users.<u>` carries only an identity, an affordance set, and the mode it was bound in.**
  There is nothing else about a power for a bind to bridge.

## Considered alternatives

- **Derive the run set from affordances** — rejected above; it is the fusion, restated.
- **A host-level `contract.affordances` applying to every user** — rejected: it was the old shape,
  and it forced a per-person decision to be stated machine-wide, which is exactly backwards for the
  one kind of statement that *is* about people.
- **Let `contract.modes` exclude the floor** — rejected: a host that runs no terminal session has no
  fallback, and every selection needs one.
