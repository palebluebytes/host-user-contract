# host↔user contract

The shared **contract** a NixOS fleet's hosts and users agree on, so **any host can enable any
user**. It is neither host nor user: it is the negotiated interface between them, and it depends on
nothing but nixpkgs `lib` — no home-manager, no packages.

The thing it is for: a seat host runs a greeter, somebody walks up and types a flake URL, a username
and a password, and their machine is there — with a desktop, by default, because nobody had to
declare anything in advance. Everything else is the build-time version of that same handshake.

Two repos meet here. A **users repo** builds each user's home ahead of time and publishes it; a
**host repo** binds the one matching what it is willing to confer. Neither knows the other's
internals.

```
users repo                          the contract                      host repo
  users/<u>/user.nix    ──build──▶  mkContractFleet   ──index──▶  bindContractUser
  users/<u>/identity.json                                          (+ what it affords)
```

---

## Quickstart

### I have a host

A host says two different kinds of thing, and keeping them apart is the shape of the whole design.

**What this machine *is*** — declared once, for the box:

```nix
contract.modes = [ "gui" ];      # this machine has a display
```

**What each person *may do*** — declared at each bind, which already names them:

```nix
# flake.nix
inputs.contract.url = "github:palebluebytes/host-user-contract";
inputs.contract.inputs.nixpkgs.follows = "nixpkgs";
inputs.users.url = "github:you/users";          # a users repo, below
inputs.users.inputs.contract.follows = "contract";

# a host module
{
  contract.modes = [ "gui" ];

  imports = [
    inputs.contract.nixosModules.default

    (inputs.contract.lib.bindContractUsers {
      source = inputs.users;
      users = {
        ada   = { };                 # nothing afforded — the MACHINE gives her the desktop
        cleo.containers = true;
        admin.sudo      = true;
      };
    })
  ];
}
```

That input pins `main`, which is the recommended pin: your `flake.lock` already holds the exact
revision, so updates happen when you run `nix flake update` and never behind your back. Tagged
releases exist alongside it, each carrying a generated `CHANGELOG.md` (written at the repo root by
release-please when the first release cuts).

**Compatibility is by major version.** A contractPackage your users repo published keeps binding on
a host that has moved on — until a major release, which is refused by name. Pre-1.0 the minor plays
the major's part, so `0.3.1` and `0.3.9` are compatible while `0.4.0` is not
([ADR-0024](docs/adr/0024-versioned-releases.md)). Keeping
`inputs.users.inputs.contract.follows = "contract"` (above) sidesteps the question entirely: both
sides are then the same contract.

Each name appears once, as the key of its own settings. It is **not** the account's name — that
comes from the user's own `identity.json`, and the producer refuses to publish a user whose key and
identity disagree, so the two are one answer. The name does **selection**: a users repo holds more
people than any one machine wants. `all = true` is for a host that wants the lot.

A user can come from somewhere else — `admin = { sudo = true; source = otherUsers; };` — so one host
can bind across repos, and `source` is per-user with the top-level one as the default.

**A display is a fact about the hardware; sudo is a judgement about a person.** A headless server
does not *decline* to give Ada a desktop — it *cannot* run one. So the two live in different
places: `contract.modes` once for the box, `affordances` at the bind that names the user.

`contract.modes` is fail-closed and the floor is implicit: a host that says nothing runs `cli` and
only `cli`. It is a **set**, not a sequence — `[ "gui" ]`, `[ "gui" "cli" ]` and `[ "cli" "gui" ]`
are one declaration, and there is no spelling that excludes the floor.

**Which powers an account holds is the host's decision alone** — there is no user-side veto to
negotiate with, and no host-wide default for a bind to inherit, so giving one account sudo and
another none is the same one mechanism written twice.

### I have a users repo

One directory per user, holding an identity, a declaration, and whatever home modules the
declaration points at:

```
users/
  ada/
    identity.json     # name, email, username, hashedPassword, sshKey — who you are, not what you may do
    user.nix          # which session shapes ada runs in, and the home for each
    home.nix          # an ordinary home-manager module
```

`user.nix` is the **whole** of what a user says:

```nix
{
  contract.cli = {
    enable        = true;
    configuration = ./home.nix;
  };
  contract.gui = {
    enable        = true;
    configuration = ./home.nix;   # or ./gui.nix, if this session needs different content
    desktop       = "plasma";     # a free-form name the seat maps to a real desktop
  };
}
```

Which sessions this user runs in, the home to build for each, and that session's own parameters.
Nothing else — in particular a user does **not** ask for features. The one refusal a user actually
needs, *never give me a desktop*, is already here: don't enable the gui mode, and no host can select
a gui home that was never built.

Two modes may name the same module — the common case, where a home does not depend on the session.
Point them at different modules when the content genuinely differs (a sway config has no terminal
equivalent), which is exactly why a mode is a mode: content cannot be injected into a sealed
derivation, so those are two derivations rather than one home with a switch in it.

The flake maps over that directory. Adding a user means adding those files and editing nothing:

```nix
fleet = contract.lib.mkContractFleet {
  members    = contract.lib.mkMembers { usersDir = ./users; };
  homeMatrix = contract.lib.mkHomeMatrix {
    systems = {
      x86_64-linux    = { };          # `{ }` = every mode; a row states only what it takes away
      aarch64-linux.gui = false;      # a headless builder tier
    };
  };
  pkgsFor   = sys: nixpkgs.legacyPackages.${sys};
  defaultSystem = "x86_64-linux";     # which system `homeConfigurations` publishes on
  buildHome = { member, mode, pkgs }: contract.lib.mkContractHome {
    inherit member mode pkgs;
    homeManagerConfiguration = home-manager.lib.homeManagerConfiguration;
    stateVersion = "25.11";
  };
};
# → inherit (fleet) homes homeConfigurations packages contractUsers;
```

It builds every member for every mode its system's row names **and** the user runs in, instantiates
`pkgs` once per system (never once per user, or evaluation time multiplies), and hands back both
flake outputs already nested by system. Your builder stays yours — the contract applies it and never
imports home-manager. Reach for `mkContractUsers` / `mkContractUser` when your build is *not* every
member × every mode. [`examples/users/`](examples/users/) is the worked multi-system version, with
checks.

`homeConfigurations` is the flat `<user>-<mode>` adapter `home-manager switch --flake .#ada-gui`
resolves. The flat naming is not your repo's choice — home-manager's CLI quotes the fragment before
it reaches Nix, so no nested spelling resolves — which is why the producer owns it rather than every
users repo re-folding it. `defaultSystem` says which system it publishes on, and a fleet baking for
a single system need not say.

### I have a seat, and I want people to just log in

```nix
{
  imports = [ contract.nixosModules.greeter ];
  contract.modes = [ "gui" ];             # this seat has a display
  contract.greeter.enable = true;
  contract.greeter.homeBuilder = "…";     # your `nix build` one-liner
  contract.greeter.desktops.plasma.command = "…";
}
```

No user is named. The greeter authenticates on `identity.json` **before any of the user's Nix
runs**, reads the modes they publish off their own flake, intersects those with what this seat
runs, builds that home and realizes the account.

It confers the **safe set** — every feature conferring no privileged group — which is now
**empty**: a stranger gets a *session*, not powers. The desktop they get comes from
`contract.modes`, and it is why a seat with no display no longer claims to offer one.

---

## The vocabulary

Each word means one thing, everywhere.

| word | is |
| --- | --- |
| **feature** | a POWER a host confers on a PERSON: `sudo`, `containers`, `virtualization`, `nix-daemon`. Every one is privileged |
| **affordance** | what a host is willing to confer on one user, stated at the bind: `{ sudo = true; }` |
| **grant** | what that user therefore holds. On the declarative path the grant *is* the affordance; a greeter confers the (empty) safe set |
| **granted** | a grant seen as an *option path* (`contract.users.<u>.granted`) — never an argument |
| **mode** | the session shape a home is BUILT for (`cli`, `gui`) — and, on the host side, a CAPABILITY of the machine. Exactly one per home |
| **home** | one built home, identified by its mode: `homes.<system>.<user>.<mode>` |
| **contractPackage** | what gets published per home (activation script + a manifest sidecar) |
| **member** | one user in a users repo: `{ name; dir; identity; declaration; }` |

**The two registries touch nowhere.** `modes.nix` answers *what session shapes exist* — asked from
one end by a user ("which do I run in?") and from the other by a host ("which can this box run?").
`features.nix` answers *what powers a host can confer on a person*. No value crosses between them.

A home is **built ahead of time**, so a host can only *pick* one — never adjust it. That is the
other reason mode and grant are different words: a grant is the part a bind *can* still confer at
activation, and a mode is the part it cannot. A user says which modes it runs in, the producer's
`mkHomeMatrix` says which its systems can build, and what gets published is the intersection.

---

## The surface

Three of them, answering three questions. **`lib`** is the contract's own functions — a host
*binds*, a producer *bakes*. The **check kit**, inside `lib`, hands a consumer the *technique* for
proving a claim about its own repo. **`testing`** hands over a *machine*: it boots a seat host, and
the claim stays the caller's to write.

### `lib` — the functions

| function | takes | gives |
| --- | --- | --- |
| `bindContractUsers` | `{ source; users; all ? false }` | a NixOS module — **a host's whole user list** |
| `bindContractUser` | `{ source; username; affordances ? {} }` | the singular underneath |
| `mkMembers` | `{ usersDir }` | `{ <name> = { name; dir; identity; declaration; }; }` |
| `mkHomeMatrix` | `{ systems }` | `{ <system> = [ <mode> ]; }` — the modes each system bakes |
| `mkContractFleet` | `{ members; homeMatrix; pkgsFor; buildHome; defaultSystem ? null }` | `{ homes; homeConfigurations; packages; contractUsers; systems; pkgsBySystem; }` |
| `mkContractHome` | `{ homeManagerConfiguration; pkgs; member; mode; stateVersion; extraModules ? [] }` | a built home |
| `mkContractUser` | `{ pkgs; member; homes }` | `{ packages.<sys>; contractUsers.<sys>.<u>; }` |
| `mkContractUsers` | `{ pkgs; members; homes }` | the same, for every member |
| `evalUser` | `{ userFile }` | a user's evaluated declaration — no build |
| `enabledModesOf` | a declaration | the modes it enables |
| `loadIdentity` | a path | the identity, complete (parsed, checked, defaults filled) |
| `resolveIdentity` | a partial identity | the same completion, without a file |
| `renderNixConfig` | settings | a `NIX_CONFIG` string |

Without a member, `mkContractUser` takes `name` + `usersDir` and `mkContractHome` takes `memberDir`
— a single-user repo needs no member set. A field passed *beside* a member must agree with it.

### `lib` — the check kit

Proofs only a **consumer** can run, over material only it has. The contract hands over the
technique, not the verdict.

| check | proves |
| --- | --- |
| `mkConfinementCheck { buildHome; pkgs; }` | your *real* module set has no system channel (positive control included) |
| `mkIdentityPostureCheck { identities; require; pkgs; }` | every `identity.json` carries the hash strength you chose |
| `mkHomeEvalCheck { homesFor; systems; pkgs; }` | every home you build evaluates, on every system you build for |
| `mkMemberChecks { members; homes; buildHome; require; pkgs; }` | all three, across every member, in one call |

Use the adapter unless your fleet builds different members on different systems — a hand-listed
check set always misses the member somebody forgot to add, and a missing check reads exactly like a
passing one.

Two more, which prove nothing and report everything — one for each side of where a verdict is
reached:

| function | does |
| --- | --- |
| `mkClaimReport { name; title; claims; pkgs; proofs ? { } }` | runs your named `{ name; ok; }` claims, prints an `ok`/`FAIL` line each, threads `proofs` (derivations whose *being built* is the verdict) in as build inputs, and fails the build if anything failed |
| `mkProofPrelude "<proof name>"` | the shell an execution proof opens its builder with: a `fail <message>` that writes `<proof name>: <message>` to stderr and exits non-zero |

An empty claim list is refused: a report folded over nothing prints a header and passes. So is an
unusable proof name — empty, multi-line, or carrying shell syntax that would escape the `echo` it
is interpolated into.

```nix
pkgs.runCommand "shared-code-per-user-data" { } (
  contract.lib.mkProofPrelude "shared-code-per-user-data"
  + ''
    [ "$markerA" = "$markerB" ] || fail "the overlay produced a different package per user"
    touch $out
  ''
)
```

### `testing` — the seat harness

The scaffolding for booting a **contract seat host** in a NixOS VM test: the boot base, the greeter
preamble and greetd wiring, and the fixtures a seat test varies against. It is what the contract's
own ten runtime proofs are built on, published so a consumer's VM test binds that same harness
rather than re-authoring a seat host free to drift from it.

| output | takes | gives |
| --- | --- | --- |
| `testing.mkSeatHarness` | `{ pkgs; system; contractModule; greeterModule ? null }` | `{ mkSeatVM; signer; signerPub; testIdentity; activationStub; }` |

`mkSeatVM` takes what one seat VM *varies* — `{ name; testScript; greeter ? true; graphical ? false;
autologin ? null; seat ? { }; modes ? [ "gui" ]; }` — and returns the assembled `runNixOSTest`. Hand
it `greeterModule` only for a seat that enables the greeter.

```nix
mkSeatVM = (contract.testing.mkSeatHarness {
  inherit pkgs system;
  contractModule = contract.nixosModules.default;
  greeterModule = contract.nixosModules.greeter;
}).mkSeatVM;
```

### Modules

| output | for |
| --- | --- |
| `nixosModules.default` | every host — `contract.modes`, the account schema and the realization |
| `nixosModules.greeter` | a seat host — the opt-in runtime greeter (greetd, eval-free auth, mode selection) |
| `homeModules.default` | every home — the `contract.identity` it is handed |
| `homeModules.baseline` | universal home hygiene, composed by `mkContractHome` by default |

### Data

`features` and `modes` (the two registries — every feature and mode surface is a projection of one
of them), `featureGroups`, `privilegedGroups`, `safeSet` (currently empty), `floorMode` (the one
mode every host runs), `greeterAffordances`, `tier1EvalConfig`, `identityFile`, `identitySchema`.

The contract handles **no secrets** beyond the login credential.

---

## Reference implementations

The positive-space counterpart to the synthetic conformance suite:

- [`examples/users/`](examples/users/) — a **users repo**. `ada` (portable — gui on one host, cli on
  another), `ben` (one line, terminal only), `cleo` (a host confers her `containers`), `svc` (runs
  in a terminal and nowhere else, so no host can give it a desktop), `admin` (break-glass sudo), and
  the `duo-a`/`duo-b` pair sharing one module + overlay — `duo-a` with genuinely different content
  per mode.
- [`examples/fleet/`](examples/fleet/) — a **host repo**: `desk` (a seat: declares `gui`, confers
  `containers` to one user and `sudo` to another, and affords ada nothing at all), plus headless
  `vault` (which names the per-user `source` key explicitly) and `agent`. With a VM test that boots a
  seat and provisions a real home end-to-end.

## Verifying

Each example carries its own checks, because they need home-manager and the contract does not input
it. "Run everything" is three targets:

```
nix flake check .              # the contract
nix flake check examples/users # the reference users repo
nix flake check examples/fleet # the reference host repo
```

## Design

Every decision, with its rationale and what was rejected, is in [`docs/adr/`](docs/adr/).
[`CONTEXT.md`](CONTEXT.md) is the glossary — the index of *language*, not decisions.
