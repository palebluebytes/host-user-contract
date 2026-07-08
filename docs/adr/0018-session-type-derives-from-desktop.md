# Session type derives from the desktop; `gui.session` is retired as user-facing vocabulary

**Status:** Accepted; extends [ADR-0013](0013-per-user-desktop-choice-host-offered.md) to the build-time path and supersedes the user-facing `gui.session` option of [ADR-0003](0003-feature-configuration-aggregates.md). Implementation staged — the build-time desktop→type derivation is the pending slice; the ADR-0003 union mechanic itself stands.

A GUI user expresses two overlapping things today: `gui.desktop` (a free-form desktop name, ADR-0013) and `gui.session` (a `wayland`/`x11` enum, ADR-0003). But a session **protocol** is not something a user has an independent preference about — it is a property of the desktop they chose. GNOME is Wayland; i3 is X11; the user cares about the desktop, and the protocol follows.

The runtime path already embodies this. [ADR-0013](0013-per-user-desktop-choice-host-offered.md) made session type "a per-desktop property" and had it *subsume* ADR-0010's `session.{wayland,x11}`: `greeter/session.nix` derives `XDG_SESSION_TYPE` from the seat's `desktops.<name>.type`, and never reads `gui.session`. `gui.session` survives only on the build-time gui-union, which predates the desktop-choice model — when ADR-0003 was written, "desktop" was not yet a modeled concept, so the session *protocol* was the finest grain available to express "what display environment does this user want."

## Decision

**Session type is a derived property of the chosen desktop, never user-owned vocabulary.** A user expresses only `gui.desktop`; wayland-vs-x11 is derived from it on both paths.

- **Runtime path** — unchanged: the seat maps `gui.desktop` → `desktops.<name>.type` and the launcher derives `XDG_SESSION_TYPE` from it (ADR-0013).
- **Build-time path** — the gui-union (ADR-0003) derives each granted user's session type from their `gui.desktop` via a **host desktop→type map** (analogous to the seat's `desktops.<name>.type`), then unions the *derived* types into `custom.gui.surface`. The map is a small host binding: a host that enables a desktop already has its `wayland-sessions/`/`xsessions/` entry, which encodes the type. The contract stays package-free (ADR-0004) — it consumes the map, it does not introspect session files.
- **`gui.session` is retired** as a user-facing feature-configuration/request option.

ADR-0003's aggregation mechanic — a host-affecting preference unioned across granted users so they do not fight over the display singleton — is untouched; it now unions derived types rather than a raw user field, so its conflict-dissolving property holds unchanged.

## Consequences

- One vocabulary everywhere: `gui.desktop` travels with the identity (the portable-user north star, ADR-0012) and yields both the launched desktop (runtime) and the provisioned surface (build-time). A user never states a protocol.
- The build-time path gains one host binding (desktop→type), the build-time analogue of the seat's `desktops`. Until it lands, `gui.session` may remain as an internal compatibility shim, but it is no longer part of the user-facing schema.
- Touch points when implemented: `features.nix` (the `gui` `config` drops `gui.session`), `realization.nix` (the gui-union reads a derived type), and the conformance fixtures that set `gui.session` (they set `gui.desktop` + the host map instead).
- The site's `gui.session` examples (how-to, features registry) describe current code and stay accurate until the change lands; they are revised then.

## Considered Options

- **Keep both parameters** — rejected: the user would express a *protocol* on the build-time path and a *desktop* on the runtime path for the same intent, contradicting ADR-0013's established principle and the portable-user north star. Two vocabularies for "what display environment do I want."
- **Have the contract introspect session files to derive type** — rejected: the contract is package-free (ADR-0004) and does not read the host's packages. The desktop→type map is a host binding, exactly like the seat's `desktops`.
- **Let a user express a bare protocol ("X11, any desktop")** — rejected as a first-class field: it is expressible as a seat/host default desktop per type, and reintroduces the very protocol-as-preference this ADR removes.
