# The contract is display-server-agnostic; the seat owns session type and launch

**Status:** Accepted. **Supersedes** [ADR-0018](0018-session-type-derives-from-desktop.md) (session type derives from the desktop) and the **gui-session union** of [ADR-0003](0003-feature-configuration-aggregates.md). **Refines** [ADR-0013](0013-per-user-desktop-choice-host-offered.md): the seat's desktop binding drops its `type` field.

[ADR-0003](0003-feature-configuration-aggregates.md) had the realization *union* every granted gui user's session type into `custom.gui.surface.{wayland,x11}`; [ADR-0018](0018-session-type-derives-from-desktop.md) then made that type a *derived* property of the user's desktop, via a host `custom.gui.desktops` name→type map. On the greeter path, `custom.greeter.desktops.<name>.type` set `XDG_SESSION_TYPE`. All of this means the **contract knows and decides display-server policy** — it carries `wayland`/`x11` in its schema, its realization, and its launcher.

But wayland-vs-x11 is not a portable property of a *user*, and it is not a cross-user quantity the contract needs to compute. It is entirely a property of **how a seat renders and launches a desktop** — and a desktop's launch command already fully determines it (`startplasma-wayland` *is* a wayland session; a command that needs `XDG_SESSION_TYPE` sets it itself, as the reference GNOME binding already does). The session type in the contract is redundant leakage of host display policy into the shared schema.

## Decision

**The contract is display-server-agnostic. It carries only the gui GRANT and the user's free-form desktop NAME; it never names, derives, or decides wayland vs x11.**

- The realization exposes only **`custom.gui.surface.enabled`** — "some gui user is granted, so this host needs a shared display surface." There is no `surface.wayland`/`surface.x11`, no `custom.gui.desktops` map, and no session-type union.
- The greeter's seat binding `custom.greeter.desktops.<name>` carries only a **self-contained `command`** — no `type`. The seat owns the session: the command sets its own `XDG_SESSION_TYPE`/session env if the desktop needs it, and `greeter/session.nix` just execs it.
- The **seat** decides its display server. A host that sees `custom.gui.surface.enabled` brings up whatever session it chooses (e.g. wayland), in its own display binding (`gui-desktop.nix` at build time, `custom.greeter.desktops` at a greeter) — the contract is not consulted.

## Consequences

- **Removed from the contract:** `custom.gui.desktops`, `custom.gui.surface.{wayland,x11}`, the gui-session union (`sessionTypeOf`/`anyWayland`/`anyX11` in `realization.nix`), the greeter `desktops.<name>.type` field, and `greeter/session.nix`'s `XDG_SESSION_TYPE` plumbing.
- A consuming host's display binding is now unconditional about its display server. The fleet's `gui-desktop.nix` enables a wayland session whenever `surface.enabled`, with no `surface.x11`/`surface.wayland` branch.
- **[ADR-0018](0018-session-type-derives-from-desktop.md) is fully superseded** — session type is not even *derived* by the contract; it is simply absent. **[ADR-0003](0003-feature-configuration-aggregates.md)'s gui-session union is superseded** — there is no cross-user session aggregation. ADR-0003's *general* "host-affecting feature configuration aggregates across granted users" principle stands as a design idea, but has no current instance.
- **[ADR-0013](0013-per-user-desktop-choice-host-offered.md) is unchanged** in substance — a user still carries a free-form `gui.desktop` name, the seat still offers desktops and resolves/launches the chosen one — *except* the seat's `desktops.<name>` binding no longer has a `type`; the launch `command` owns the session env.
- **Conformance:** the surface-union assertions (`surface.wayland`/`surface.x11`, "offers both sessions", "x11-only"/"wayland-only") and the two-session union VM are removed. The remaining gui invariant is: a granted gui user ⇒ `surface.enabled == true`; none ⇒ `false`. Greeter session/desktop VMs still launch real sessions via the seat's self-contained command.

## Considered Options

- **Keep the derived session type in the contract (ADR-0018)** — rejected: it still makes the contract encode display-server policy. A desktop's command already determines its session, so the derivation is redundant, and "the contract carries wayland/x11" is exactly what this removes.
- **Contract offers a wayland/x11 *hint* the seat may ignore** — rejected: any x11/wayland vocabulary in the contract is the leakage being removed; the seat's command needs no hint from the contract.
- **Leave it, since the fleet is wayland-only anyway** — rejected: the mechanism was live in the schema, conformance, and greeter, and it broke a real host on a contract bump. A display-agnostic contract is simpler and matches the contract's package-free, host-renders-policy stance ([ADR-0004](0004-extract-contract-flake.md)/[ADR-0005](0005-platform-backend-agnostic-secrets.md)).
