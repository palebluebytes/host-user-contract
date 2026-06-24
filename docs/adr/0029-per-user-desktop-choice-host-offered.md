# A greeter login is a per-user desktop choice; the seat offers desktops, the contract carries the name

**Status:** Accepted; refines [ADR-0026](0026-greeter-seat-baseline-not-per-login-rebuild.md) (session launch, step 8) for full desktop environments.

ADR-0026's session launch keyed only on **session type** (`wayland`/`x11`) bound seat-wide. That cannot express the real requirement: user A logs into **GNOME**, logs out, user B logs into **Plasma**, on the same seat — different *desktops*, chosen *per user*, which is the experience non-technical users need. The seat mechanism already supports the sequencing (greetd serialises `seat0`; each login is a fresh seat session — GNOME→Plasma is the same DRM handoff as any compositor swap); what was missing is *which* desktop each user gets.

## Decision

A greeter login launches the **user's chosen desktop**, from the set the **seat offers**.

- **The user carries the choice** (portable-user north star, ADR-0028): `contract.requests.gui.desktop = "<name>"` — a **free-form** name in the user's home, so it travels with the identity and yields the same desktop on every seat that offers it. Free-form keeps the contract **DE-agnostic** ([ADR-0020](0020-extract-contract-flake.md)/[ADR-0021](0021-platform-backend-agnostic-secrets.md)): the contract carries an opaque preference; the seat maps it to a real DE. An un-offered or unknown name **degrades to the seat default**, never breaks the login — the same "unknown requests degrade silently" posture requests already have ([ADR-0018](0018-user-confinement-manifest-greeter.md)).
- **The seat offers desktops** (host binding, the greeter-seat baseline): `custom.greeter.desktops.<name> = { type = "wayland"|"x11"; command = <session Exec>; }`, with `custom.greeter.defaultDesktop`. The operator enables the DEs the seat provides (whose generated `wayland-sessions/*.desktop` `Exec` lines are the `command`) — exactly what a display manager launches. This **subsumes** ADR-0026's `session.{wayland,x11}` (type becomes a per-desktop property).
- **The greeter resolves + launches**: `contract-greeter-session` reads the user's surfaced desktop choice, matches it against the offered `desktops` (else the default), and execs that desktop's command **as the user in greetd's seat session** — a full DE gets the systemd-user instance + D-Bus + DRM it needs, which a bare compositor `exec` does not provide. Window managers still work — they are just `desktops` entries with no special needs.

## Consequences

- The `gui` feature gains a `desktop` request field (a new projection alongside `gui.session`); `gui.session` stays for the build-time gui-union ([ADR-0019](0019-feature-configuration-aggregates.md)).
- The user's desktop choice must be **surfaced** from the home eval to the launcher (the greeter runs before reading the home's Nix); the reference does this via a file the home materialises (`~/.contract-desktop`). Auto-materialising it from `contract.requests.gui.desktop` is a small contract home-side helper.
- **Full DEs are heavy**: launching GNOME/Plasma under greetd (rather than GDM/SDDM) is supported but the VM render tests are large and slow, so they are host-integration-grade (the consumer-renders boundary, like the gui-union VM rendering Plasma via a host SDDM binding). The fast contract tests prove the *mechanism* — per-user desktop selection + sequential different-desktop logins — with lightweight compositors.

## Considered Options

- **Contract-side desktop enum (`gnome | plasma | …`)** — rejected: the contract would have to know every DE and cut a release to add one, against its DE-agnostic stance. Free-form + seat-side mapping keeps DEs a host concern.
- **Desktop choice in `identity.json`** — rejected: the DE is *experience*, not identity; it belongs in the home (`contract.requests`) so it travels as part of the portable home, not the credential.
- **Seat-wide single desktop** (one DE per seat) — rejected: defeats per-user choice on a shared seat, the whole point.
