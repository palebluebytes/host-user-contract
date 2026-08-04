# ada — the multi-machine (portable) reference user (ADR-0007 home shape, consumed per ADR-0016).
#
# ONE identity, ONE home, that logs in as a GUI user on the seat host and a CLI-only user on a
# headless host — the session modality is decided by each HOST's grant, never by ada. This home
# does nothing to make that happen beyond OFFERING its desktop choice: the contract bridges the
# gui request into the account ONLY where the host granted gui (bindUser's `bridgeRequests`), so
# the SAME contractPackage yields a gui account on `workstation` and a silently-degraded cli
# account on `agent` — the home-side of the contract's silent-degradation promise (ADR-0002),
# with no per-host branching in the home at all.
#
# Deliberately contract-pure (ADR-0008): it sets only the contract.requests namespace, never
# home-manager's own home.*/programs.* — so the same module evaluates headlessly against the bare
# contract umbrella when the conformance tracer harvests requests (no home-manager). The identity
# is injected by the binding (ADR-0009); this home never loads identity.json itself.
{ ... }:
{
  # ada's DESKTOP choice (ADR-0013): a free-form, DE-agnostic name that travels with the home. It
  # is inert until a host GRANTS gui — then the seat maps it to a real desktop (else its default).
  contract.requests.gui.desktop = "plasma";
}
