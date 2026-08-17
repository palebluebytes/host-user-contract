# host↔user contract

The shared **contract** a NixOS fleet's hosts and users agree on, so any host can enable any user —
and deny features a user introduces — on rebuild. It is neither host nor user: it is the negotiated
interface between them, and it depends on nothing but nixpkgs `lib`.

Two repos meet here. A **users repo** builds each user's home ahead of time and publishes it; a
**host repo** picks the one matching what it is willing to grant. Neither knows the other's
internals.

```
users repo                        the contract                    host repo
  users/<u>/home.nix   ──build──▶  mkContractUser   ──index──▶  bindContractUser
  users/<u>/identity.json                                        (grant = affordances ∩ offer)
```

---

## Quickstart

### I have a host

Two lines, plus what you are willing to grant.

```nix
# flake.nix
inputs.contract.url = "github:palebluebytes/host-user-contract";
inputs.contract.inputs.nixpkgs.follows = "nixpkgs";
inputs.users.url = "github:you/users";          # a users repo, below
inputs.users.inputs.contract.follows = "contract";

# a host module
{
  imports = [
    inputs.contract.nixosModules.default
    (inputs.contract.lib.bindContractUser { usersFlake = inputs.users; username = "ada"; })
  ];

  # what this host is willing to grant to users who ask for it
  contract.affordances = {
    gui.enable = true;
    sudo.enable = false;
  };
}
```

A user gets a feature only if **the host affords it and the user asked for it**. There is no way to
grant a user something they did not ask for.

### I have a users repo

One directory per user, holding exactly two files:

```
users/
  ada/
    identity.json     # name, email, username, hashedPassword, sshKey…
    home.nix          # a normal home-manager module, plus `contract.wants`
```

`home.nix` says what this user asks a host for:

```nix
{ hostFacts, ... }:
{
  contract.wants.gui.enable = true;              # ask for a desktop
  contract.requests.gui.desktop = "plasma";      # …and which one

  # a home may branch on a grant only where something builds for it
  custom.home.profiles.gui.enable = hostFacts.granted.gui.enable or false;
}
```

The flake maps over that directory. Adding a user means adding those two files and editing nothing —
one system shown here, and the whole thing is eleven lines:

```nix
let
  pkgs    = nixpkgs.legacyPackages.x86_64-linux;
  members = contract.lib.mkMembers { usersDir = ./users; };

  # which homes does this system need? `{ }` = its seats can use everything the contract names.
  rows = (contract.lib.mkHomeMatrix { systems.x86_64-linux = { }; }).x86_64-linux;

  # build one home per row, and hand the row back with its home attached
  homesFor = member: map (row: row // {
    home = contract.lib.mkContractHome {
      inherit member pkgs;
      inherit (row) grants;
      homeManagerConfiguration = home-manager.lib.homeManagerConfiguration;
      stateVersion = "25.11";
    };
  }) rows;
in
contract.lib.mkContractUsers {
  inherit pkgs members;
  homes = lib.mapAttrs (_: homesFor) members;
}
# → { packages.x86_64-linux.<u>-contractPackage-<label>; contractUsers.x86_64-linux.<u>; }
```

`inherit … packages contractUsers` those straight into your flake outputs and a host can bind them.

For more than one system, fold the same block over your system list — and instantiate `pkgs` **once
per system**, never once per user, or evaluation time multiplies. [`examples/users/`](examples/users/)
is a worked multi-system version with checks.

---

## The vocabulary

Six words. Each means one thing, everywhere.

| word | is |
| --- | --- |
| **grants** | a grant attrset, `{ gui.enable = true; }` — the name of every *argument* holding one |
| **grantKey** | its sorted feature names, `[ "gui" ]` — the identity of one home |
| **granted** | the same attrset seen as an *option path* (`hostFacts.granted`) — never an argument |
| **home** | one built home, plus the grants it was built for |
| **contractPackage** | what gets published per home (activation script + a manifest sidecar) |
| **member** | one user in a users repo: `{ name; dir; identity; }` |

A home is **built ahead of time**, so a host can only *pick* one — never adjust it. That is why a
user needs more than one: `mkHomeMatrix` says which.

---

## The surface

### `lib` — the functions

| function | takes | gives |
| --- | --- | --- |
| `mkMembers` | `{ usersDir }` | `{ <name> = { name; dir; identity; }; }` |
| `mkHomeMatrix` | `{ systems }` | `{ <system> = [ { grants; label } ]; }` |
| `mkContractHome` | `{ homeManagerConfiguration; pkgs; member; grants ? {}; stateVersion; extraModules ? []; }` | a built home |
| `mkContractUser` | `{ pkgs; member; homes }` | `{ packages.<sys>; contractUsers.<sys>.<u>; }` |
| `mkContractUsers` | `{ pkgs; members; homes }` | the same, for every member |
| `bindContractUser` | `{ usersFlake; username }` | a NixOS module |
| `traceUser` | `{ userModule; identity; grants ? {}; }` | a dry-run record — no home-manager, no build |
| `loadIdentity` | a path | the identity |
| `hostFactsFor` | `{ grants ? {}; platform; exposed ? false; }` | `{ exposed; platform; granted; }` |
| `renderNixConfig` | settings | a `NIX_CONFIG` string |

Without a member, `mkContractUser` takes `name` + `usersDir` and `mkContractHome` takes `memberDir`
— a single-user repo needs no member set. A field passed *beside* a member must agree with it.

### `lib` — the check kit

Proofs only a **consumer** can run, over material only it has. The contract hands over the
technique, not the verdict.

| check | proves |
| --- | --- |
| `mkConfinementCheck { buildHome; pkgs; }` | your *real* module set has no system channel (positive control included) |
| `mkIdentityPostureCheck { identities; require; pkgs; }` | every `identity.json` carries the hash strength you chose (ADR-0019) |
| `mkHomeEvalCheck { homesFor; systems; pkgs; }` | every home you build evaluates, on every system you build for |
| `mkMemberChecks { members; homes; buildHome; require; pkgs; }` | all three, across every member, in one call |

Use the adapter unless your fleet builds different members on different systems — a hand-listed
check set always misses the member somebody forgot to add, and a missing check reads exactly like a
passing one.

### Modules

| output | for |
| --- | --- |
| `nixosModules.default` | every host — the `custom.users` schema, the realization, `contract.affordances` |
| `nixosModules.greeter` | a seat host — the opt-in runtime greeter (greetd, eval-free auth) |
| `homeModules.default` | every home — `identity`, `contract.wants`, `contract.requests` |
| `homeModules.baseline` | universal home hygiene, composed by `mkContractHome` by default |
| `homeModules.greeterDesktop` | opt-in: surfaces the desktop choice for the greeter |

### Data

`features` (the single registry — everything else is a projection of it), `featureGroups`,
`privilegedGroups`, `safeSet`, `homes`, `greeterGrants`, `tier1EvalConfig`, `identityFile`,
`identitySchema`.

The contract handles **no secrets** beyond the login credential (ADR-0023).

---

## Reference implementations

The positive-space counterpart to the synthetic conformance suite (ADR-0022):

- [`examples/users/`](examples/users/) — a **users repo**. `ada` (portable — gui on one host, cli on
  another), `ben` (rides the defaults), `cleo` (asks for `containers`), `svc` (opts *out* of gui, so
  no host can grant it one), `admin` (break-glass sudo), and the `duo-a`/`duo-b` pair sharing one
  module + overlay.
- [`examples/fleet/`](examples/fleet/) — a **host repo**: `desk`, `vault` and `agent` binding those
  users, with a VM test that boots a seat and provisions a real home end-to-end.

## Verifying

Each fleet carries its own checks, because they need home-manager and the contract does not input
it. "Run everything" is three targets:

```
nix flake check .              # the contract
nix flake check examples/users # the reference users repo
nix flake check examples/fleet # the reference host repo
```

## Design

Every decision, with its rationale and what was rejected, is in [`docs/adr/`](docs/adr/). Start with
[`0001`](docs/adr/0001-host-user-contract.md) (the contract), then
[`0004`](docs/adr/0004-extract-contract-flake.md) (why it is this repo) and
[`0026`](docs/adr/0026-consumer-producer-public-surface.md) (why the surface is these functions).
[`CONTEXT.md`](CONTEXT.md) is the glossary — the index of *language*, not decisions.
