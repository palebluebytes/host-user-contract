# ada — the multi-machine (portable) reference user, the contract's portable-user NORTH STAR
# (ADR-0007 home shape, consumed per ADR-0016).
#
# ONE identity, ONE home, that logs in as a GUI user on the seat host and a CLI-only user on a
# headless host — whether she gets a gui or cli session is decided by each HOST's grant, never by
# ada. This home
# does nothing to make that happen beyond OFFERING its desktop choice: the contract bridges the
# gui request into the account ONLY where the host granted gui (the contract's `bridgeRequests`), so
# the SAME contractPackage yields a gui account on the seat host `desk` and a silently-degraded cli
# account on `agent` — the home-side of the contract's silent-degradation promise (ADR-0002),
# with no per-host branching in the home at all.
#
# Deliberately contract-pure (ADR-0008): it sets only the contract.requests namespace, never
# home-manager's own home.*/programs.* — so the same module evaluates headlessly against the bare
# contract umbrella when the conformance tracer harvests requests (no home-manager). The identity
# is injected by the binding (ADR-0009); this home never loads identity.json itself.
#
# ada's `identity.json` is also the members' ONE documented FULL FORM — every field the contract's
# identity schema knows, spelled out, because the schema is worth seeing written down once. Only
# `name`, `email` and `username` are REQUIRED; `gmail`, `sshKey`, `hashedPassword`, `extraGroups`
# and `trustedKeys` all carry defaults, so the other six users omit whatever nothing reads for them
# (cleo keeps `extraGroups`, everyone keeps `hashedPassword` for the login credential). ada keeps
# `sshKey` because the reference host fleet's integration VM provisions her account from this very
# file, and the greeter's `provision` writes `~/.ssh/authorized_keys` out of it. Six copies of
# `"trustedKeys": []` would have taught that the boilerplate is required, which is false.
{ ... }:
{
  # WHICH SESSIONS THIS HOME CAN RUN IN (ADR-0032). There is no default, deliberately: a user's
  # essential nature is not set by inheritance. ada says BOTH, and that is what makes her the
  # roaming north star — a gui session on the seat host and a terminal one on the headless box,
  # from one home. Say only `gui` and a headless host refuses her outright, which is the right
  # answer for a home that would land there with no display to run in.
  contract.supports.cli = true;
  contract.supports.gui = true;

  # What ada asks a host for (ADR-0028) is the SAFE-SET DEFAULT: gui is non-privileged, so it is
  # wanted with no `contract.wants` line at all. She asks for nothing privileged, so this home has
  # no want to declare — the offer the producer's flake used to carry is now simply the default.
  #
  # ada's DESKTOP choice (ADR-0013): a free-form, DE-agnostic name that travels with the home. It
  # is inert until a host GRANTS gui — then the seat maps it to a real desktop (else its default).
  contract.requests.gui.desktop = "plasma";
}
