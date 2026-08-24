# vault — a headless, NON-exposed host, and the fleet's one bind that names a per-user `source`.
#
# It declares no modes, so it RUNS the floor alone — `[ "cli" ]`, with nothing written anywhere to
# say so. No display, so no display surface and no XDG portal glue; both follow from
# `contract.modes` being empty rather than from anything about these users.
#
#   - ben: a plain reference account from the fleet's usual source. He runs in `cli`, so this host
#     has a mode of his to bind; a user who ran only in `gui` would be REFUSED here by name rather
#     than silently given a lesser home.
#   - svc: the terminal-only account, bound through its OWN `source` key rather than the top-level
#     default. That key is what lets a host draw one account from somewhere else — a contractor's
#     own flake, a second team's, an older pin held back deliberately (ADR-0015).
#
# The `svc.source` line here is not a demonstration of two repos: it names this fleet's one source,
# and this fleet has only one. What it IS is a live use of a RESERVED bind key. An unrecognised key
# in a bind is a hard error, so if `source` ever stopped being per-user, `svc.source` would be read
# as an unknown affordance and this host would stop evaluating — which is why the fleet's checks owe
# no separate claim about it, and why the second source is not worth a second repo here. The proof
# that a second source binds a member the default has never heard of is the conformance suite's, in
# `conformance/turnkey-bind.nix`; ADR-0022 records why this fleet leaves it there.
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
