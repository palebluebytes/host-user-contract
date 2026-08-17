# The roster fixture

A synthetic ADR-0020 users directory for `conformance/roster.nix`, holding the three kinds of
entry a real one can contain:

- `pip/` — a **member**: a directory with an `identity.json` (plus the `home.nix` the layout
  pairs it with, so the fixture is a faithful user directory rather than a bare identity file).
- `half-added/` — a directory with **no `identity.json`** (a user whose `home.nix` landed first).
  Not a member: the roster keys on the identity file, so a half-added directory is skipped rather
  than yielding a member whose identity throws on read.
- this file — a **non-directory** entry at the roster root. Not a member either.

The last two are the negative space, and they cannot live in `examples/users` (ADR-0022: the
reference fleet is the positive-space example a consumer copies; the synthetic suite borrows real
atoms from it, never the reverse). `half-added/` doubles as the **memberless** directory the
empty-roster error is proven against — pointed at directly, it derives no member at all.

`pip` carries no `hashedPassword`: the field is optional, and this fixture is about directory
shape, not the ADR-0019 credential posture (which `conformance/identity-posture.nix` owns).
