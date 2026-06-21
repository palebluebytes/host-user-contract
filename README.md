# host↔user contract

The shared **contract** a NixOS fleet's hosts and users agree on, so any host can enable
any user — and deny features a user introduces — on rebuild. It is neither host nor user:
it is the negotiated interface between them.

It depends on nothing but nixpkgs `lib` and evaluates standalone (no host repo). See
`docs/adr/0015-host-user-contract.md` and `0020-extract-contract-flake.md` in the
consuming repo for the design.

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
