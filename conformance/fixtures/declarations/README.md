# The declaration fixture

Two user directories that differ in exactly one line, for `conformance/declaration.nix`'s
dead-data claim:

- `dead/` — configures the gui mode (a `configuration` and a `desktop`) but never **enables** it.
  Nothing will ever build that mode, so both are dead data in the user's own repo. Every value in
  it is individually well-formed, which is why the typed schema cannot catch this by itself and a
  guard has to.
- `live/` — the byte-identical settings **with** `enable = true`. It is the control: without it,
  "the guard fires" could hold for a reason that has nothing to do with the missing `enable`.

`mkMembers` pointed at this directory therefore refuses (because of `dead/`), while `live/` alone
composes a home.
