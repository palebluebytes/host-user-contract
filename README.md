# host↔user contract

The shared **contract** a NixOS fleet's hosts and users agree on, so any host can enable
any user — and deny features a user introduces — on rebuild. It is neither host nor user:
it is the negotiated interface between them.

It depends on nothing but nixpkgs `lib` and evaluates standalone (no host repo). The full
design lives in [`docs/adr/`](docs/adr/) — start with `0001-host-user-contract.md` (the
contract), `0004-extract-contract-flake.md` (this repo), `0006`/`0007` (the greeter +
user-flake shape that consume it).

## What it ships

- `nixosModules.default` / `homeModules.default` — the umbrella kit (the `custom.users`
  schema, the host-invariant **realization**, the `custom.host.exposed` fact, and the user's own
  typed voice: `contract.wants` — which features it asks for — plus `contract.requests`, their
  parameters). A host imports these and supplies only its display/package bindings. The contract
  handles no secrets beyond the login credential (ADR-0023).
- `lib` — the derivation functions: the producer/consumer coin `mkContractUser`/`mkContractUsers`
  (a user fleet bakes its contractPackages + binding index) and `bindContractUser` (a host binds one
  indexed user, grant = affordances ∩ offer), plus `mkContractHome` (the producer home builder —
  home-manager injected per call, never a contract input; composes `homeModules.baseline`, the
  per-option-overridable home hygiene, by default, and gives the home the **grant-key it was baked
  under** so the producer coin rejects a mispaired `{ grants; home }` at bake time — ADR-0029),
  `mkContractRoster` (the ADR-0020 users directory read once into `{ <name> = { name; dir;
  identity; }; }` — the members the coin and the builder take, so no producer re-writes the layout
  rule or re-resolves an `identity.json`), `mkBakeMatrix` (the per-system **bake matrix** over
  `variants` — `{ <system> = { <axis> = bool; }; }`, a row per system the fleet bakes naming only the
  axes its *seats cannot use*; an omitted axis is **usable**, so a registry that gains one bakes it
  everywhere with no consumer edit, where a list of usable features or of labels would drop it in
  silence. *Which* variants a fleet bakes stays its fleet fact; the shape of the declaration does
  not, because an under-bake is silent — a host binds the maximal variant that exists),
  `traceUser` (dry-run inspect), `loadIdentity`, and
  `renderNixConfig`. It also ships the
  **check kit** — the proofs only a
  consumer can run, over material only it has: `mkConfinementCheck` (this repo's *real* module set
  still has no system channel — positive control included), `mkIdentityPostureCheck` (this
  repo's own roster carries the credential posture *this* repo chose, `require = "yescrypt"` for a
  public one — opt-in, because ADR-0019 makes the posture consumer-owned and `loadIdentity`
  imposes none), and `mkVariantEvalCheck` (every variant this repo bakes for one user *evaluates*
  on every system it bakes — roster-generic, applied per user by a consumer's mapper; *which*
  variants a fleet bakes per system stays the consumer's fact).
- data surface — `features` (the single registry), `featureGroups`,
  `privilegedGroups`, `safeSet`, `homeAffecting` (the grants a home may see — a producer narrows
  `hostFacts.granted` with it, and `powerset(homeAffecting)` bounds what it bakes; the per-system
  subset actually baked is the consumer's fleet fact, ADR-0028).
- `checks.<system>.conformance` — the contract's own conformance suite (synthetic users ×
  the umbrella, no host repo).

## Consume it

```nix
inputs.contract = {
  url = "github:palebluebytes/host-user-contract";
  inputs.nixpkgs.follows = "nixpkgs";
};
# then, host-side:
imports = [ inputs.contract.nixosModules.default ];
```

A feature is one entry in `features.nix`; everything else is a projection of it.

## Reference implementations

Two sibling flakes show a canonical implementation of the contract — the positive-space
counterpart to the synthetic conformance suite (ADR-0022):

- [`examples/users/`](examples/users/) — the reference **user fleet** (ADR-0020): the operator's
  own accounts in one flake, each exported as a per-user `<u>-contractPackage` output. Each declares
  what it asks a host for in its own `home.nix` (`contract.wants`, ADR-0028). Users: `ada` (portable
  — gui on one host, cli on another), `ben` (rides the safe-set default), `cleo` (privileged-group
  clamp — asks for `containers`), `svc` (the user-side veto — opts out of gui, so no host can grant it one), `admin` (break-glass — asks
  for the minimal `sudo`/wheel grant, login password `password`), plus the `duo-a`/`duo-b` pair,
  which import one shared home module + overlay from `examples/users/shared/` — the ADR-0020 "shared
  code, per-user data" ergonomic, permitted but not required (the five above share nothing).
- [`examples/fleet/`](examples/fleet/) — the reference **host fleet**: `nixosConfigurations`
  (`desk`, `vault`, `agent`) that bind those users via `bindContractUser` + `contract.affordances`,
  showing the two-repo world meeting at the binding. Its `checks` prove the fleet evaluates coherently,
  `ada` diverges gui↔cli across hosts, and the greeter provisions a real home end-to-end.

Each fleet carries its own `checks` (they need home-manager, which the contract does not input), so
"run everything" is `nix flake check` in three targets: `.`, `examples/users`, `examples/fleet`.
