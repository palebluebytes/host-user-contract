# The member set fixture

A synthetic users directory for `conformance/members.nix`, holding the three kinds of entry a real
one can contain:

- `pip/` — a **member**: a directory with an `identity.json`, its `user.nix` declaration, and the
  `home.nix` that declaration points at, so the fixture is a faithful user directory rather than a
  bare identity file.
- `half-added/` — a directory with **no `identity.json`** (a user whose `user.nix` landed first).
  Not a member: the member set keys on the identity file, so a half-added directory is skipped
  rather than yielding a member whose identity throws on read.
- this file — a **non-directory** entry at the member set root. Not a member either.

The last two are the negative space, and they cannot live in `examples/users`: the reference fleet
is the positive-space example a consumer copies, and the synthetic suite borrows real atoms from
it, never the reverse. `half-added/` doubles as the **memberless** directory the empty-member-set
error is proven against — pointed at directly, it derives no member at all.

`pip` carries no `hashedPassword`: the field is optional, and this fixture is about directory
shape, not the credential posture (which `conformance/identity-posture.nix` owns).
