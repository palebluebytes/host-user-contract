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
    gui = true;
    sudo = false;
  };
}
```

A user gets a feature only if **the host affords it and the user asked for it**. There is no way to
grant a user something they did not ask for.

That one declaration also decides which **modes** — session shapes — this host runs: the floor
(`cli`, which every host runs) plus every mode whose grant it affords. Affording `gui` means running
`{ cli, gui }`; affording nothing means running `{ cli }`. Nothing declares a mode.

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
{ config, lib, ... }:
{
  contract.supports.cli = true;                  # which sessions this home can run in
  contract.supports.gui = true;                  # (no default — say at least one)

  contract.wants.gui = true;                     # ask for a desktop
  contract.requests.gui.desktop = "plasma";      # …and which one

  # content that works in every session is written with no gate at all; only
  # session-specific content is gated, on a switch the contract writes for you
  home.file.".config/sway/config" = lib.mkIf config.custom.home.profiles.gui.enable {
    text = "…";
  };
}
```

The flake maps over that directory. Adding a user means adding those two files and editing nothing —
one system shown here, and the whole thing is eleven lines:

```nix
let
  pkgs    = nixpkgs.legacyPackages.x86_64-linux;
  members = contract.lib.mkMembers { usersDir = ./users; };

  # which modes does this system bake? `{ }` = all of them; a row states only what it takes away.
  bakedModes = (contract.lib.mkHomeMatrix { systems.x86_64-linux = { }; }).x86_64-linux;

  # build one home per mode, keyed by that mode
  homesFor = member: lib.genAttrs bakedModes (mode: contract.lib.mkContractHome {
    inherit member mode pkgs;
    homeManagerConfiguration = home-manager.lib.homeManagerConfiguration;
    stateVersion = "25.11";
  });
in
contract.lib.mkContractUsers {
  inherit pkgs members;
  homes = lib.mapAttrs (_: homesFor) members;
}
# → { packages.x86_64-linux.<u>-contractPackage-<mode>; contractUsers.x86_64-linux.<u>; }
```

`inherit … packages contractUsers` those straight into your flake outputs and a host can bind them.

For more than one system, don't fold that block by hand — hand the whole join to `mkContractFleet`,
which builds every member for every mode on every system your matrix names, instantiates `pkgs` **once
per system** (never once per user, or evaluation time multiplies), and gives back both flake outputs
already nested by system:

```nix
fleet = contract.lib.mkContractFleet {
  inherit members;
  homeMatrix = contract.lib.mkHomeMatrix { systems = { x86_64-linux = { }; aarch64-linux.gui = false; }; };
  pkgsFor    = sys: nixpkgs.legacyPackages.${sys};
  buildHome  = { member, mode, pkgs }: contract.lib.mkContractHome {
    inherit member mode pkgs;
    homeManagerConfiguration = home-manager.lib.homeManagerConfiguration;
    stateVersion = "25.11";
  };
};
# → inherit (fleet) homes packages contractUsers;   …and `fleet.homes.<sys>.<u>.<mode>` for your checks
```

Your builder stays yours — the contract applies it and never imports home-manager. Reach for
`mkContractUsers` above instead when your build is *not* every member × every mode.
[`examples/users/`](examples/users/) is the worked multi-system version, with checks.

---

## The vocabulary

Six words. Each means one thing, everywhere.

| word | is |
| --- | --- |
| **grant** | a host-side power conferred on an account at activation: `{ gui = true; }`. It rides the bind and can never change a home |
| **mode** | the session shape a home is BUILT for (`cli`, `gui`). Exactly one per home, and no bind can change it |
| **granted** | a grant attrset seen as an *option path* (`custom.users.<u>.granted`) — never an argument |
| **home** | one built home, identified by its mode: `homes.<system>.<user>.<mode>` |
| **contractPackage** | what gets published per home (activation script + a manifest sidecar) |
| **member** | one user in a users repo: `{ name; dir; identity; }` |

A home is **built ahead of time**, so a host can only *pick* one — never adjust it. That is the
whole reason mode and grant are different words: a grant is the part a bind *can* still confer, and
a mode is the part it cannot. A user says which modes it can run in (`contract.supports`), the
producer's `mkHomeMatrix` says which its systems can build, and what gets published is the
intersection.

---

## The surface

### `lib` — the functions

| function | takes | gives |
| --- | --- | --- |
| `mkMembers` | `{ usersDir }` | `{ <name> = { name; dir; identity; }; }` |
| `mkHomeMatrix` | `{ systems }` | `{ <system> = [ <mode> ]; }` — the modes each system bakes |
| `mkContractHome` | `{ homeManagerConfiguration; pkgs; member; mode; stateVersion; extraModules ? []; }` | a built home |
| `mkContractUser` | `{ pkgs; member; homes }` | `{ packages.<sys>; contractUsers.<sys>.<u>; }` |
| `mkContractUsers` | `{ pkgs; members; homes }` | the same, for every member |
| `mkContractFleet` | `{ members; homeMatrix; pkgsFor; buildHome }` | `{ homes; packages; contractUsers; systems; pkgsBySystem; }` — every member × home × system |
| `bindContractUser` | `{ usersFlake; username }` | a NixOS module |
| `traceUser` | `{ userModule; identity; grants ? {}; }` | a dry-run record — no home-manager, no build |
| `loadIdentity` | a path | the identity |
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

`features` and `modes` (the two registries — every grant and mode surface is a projection of one of
them), `featureGroups`, `privilegedGroups`, `safeSet`, `floorMode` (the one mode every host runs),
`greeterGrants`, `tier1EvalConfig`, `identityFile`, `identitySchema`.

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
