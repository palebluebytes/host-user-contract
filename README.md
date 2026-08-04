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
  schema, the host-invariant **realization**, the `platform` interface, the exposed-host
  ban). A host imports these and supplies only the `platform` *binding* (its secrets
  backend) and its display/package bindings.
- `lib` — the derivation functions a host applies to its own fleet
  (`mkFeatureRecipients`, `mkHostFacts`).
- data surface — `features` (the single registry), `featureMeta`, `featureGroups`,
  `privilegedGroups`, `safeSet`.
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
config.custom.platform = { secretFile = …; secretPath = …; };  # the host's binding
```

A feature is one entry in `features.nix`; everything else is a projection of it.

## Reference implementations

Two sibling flakes show a canonical implementation of the contract — the positive-space
counterpart to the synthetic conformance suite (ADR-0022):

- [`examples/users/`](examples/users/) — the reference **user fleet** (ADR-0020): the operator's
  own accounts in one flake, each exported as a per-user `<u>-contractPackage` output. Users:
  `ada` (portable — gui on one host, cli on another), `ben` (secret-bearing signing), `cleo`
  (privileged-group clamp), `svc` (cli-only automation), `admin` (break-glass — the minimal
  `sudo`/wheel grant, login password `password`).
- [`examples/fleet/`](examples/fleet/) — the reference **host fleet**: `nixosConfigurations`
  (`workstation`, `vault`, `agent`) that bind those user outputs via `bindContractPackage`, showing
  the two-repo world meeting at the binding. Its `checks` prove the fleet evaluates coherently,
  `ada` diverges gui↔cli across hosts, and the greeter provisions a real home end-to-end.

Each fleet carries its own `checks` (they need home-manager, which the contract does not input), so
"run everything" is `nix flake check` in three targets: `.`, `examples/users`, `examples/fleet`.
