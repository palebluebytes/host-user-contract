# vault — a headless, NON-exposed host, and the fleet's example of binding a user from ELSEWHERE.
#
# It declares no modes, so it RUNS the floor alone — `[ "cli" ]`, with nothing written anywhere to
# say so. No display, so no display surface and no XDG portal glue; both follow from
# `contract.modes` being empty rather than from anything about these users.
#
#   - ben: a plain reference account from the fleet's usual source. He runs in `cli`, so this host
#     has a mode of his to bind; a user who ran only in `gui` would be REFUSED here by name rather
#     than silently given a lesser home.
#   - svc: the terminal-only account, taken from a DIFFERENT source. A host is not restricted to one
#     users repo — a contractor's own flake, a second team's, an older pin held back deliberately —
#     so `source` is per-user, defaulting to the top-level one. Here both sources happen to be the
#     same repo, because this fleet has only one; the point is that the seam exists and is one word.
{ contract, users, ... }:
{
  imports = [
    (contract.lib.bindContractUsers {
      source = users;
      users = {
        ben = { };
        svc.source = users;
      };
    })
  ];

  networking.hostName = "vault";
}
