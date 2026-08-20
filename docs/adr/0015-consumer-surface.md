# The consumer surface: one bind for a whole fleet

**Status:** Accepted (2026-08-20). The host-repo half of
[0011](0011-prebuilt-binding-mode.md); the call [0009](0009-host-declares-modes.md) shows.

```nix
(contract.lib.bindContractUsers {
  source = users;
  users = {
    ada   = { };
    cleo  = { containers = true; };
    admin = { sudo = true; };
    svc   = { source = otherUsers; };
  };
})
```

One call, one flake, a person per key and their affordances as the value. The host holds **zero**
internals of the users repo: no package names, no directory layout, no identity paths.

`bindContractUser { source; username; affordances }` is the singular underneath — the true partner
of `mkContractUser`, and what a host binding one person reaches for.

## The username comes from the declaration, not from a parameter beside it

Passing it twice made the index key and the identity two facts that could disagree, and the
producer's own guard is the reason: it refuses to publish a user whose key and `identity.username`
differ. The bind takes the key as a **selection** — *this repo holds seven people and this machine
wants three* — and the account's name comes from the identity.

`all = true` is the other end of that: bind everybody the source publishes.

## `source`, not `usersFlake`

The old name described the argument's *type* rather than its *role*, and the type is not even
fixed — the conformance suite hands plain attrsets. What the argument means is *whatever publishes
this binding index*.

It is **per-user with a top-level default**, so one host can draw a service account from a different
repo than its people. That makes `source` a **reserved bind key**, and a reserved key inside an
attrset of feature names is a collision waiting to happen — so the contract asserts that no feature
is named `source`, on the same projection every bind reads. A feature ever given that name is a
named build error rather than a bind setting silently read as an affordance.

## What a bind does

1. Read the binding index for this system and this person.
2. Take the modes this machine runs ([0009](0009-host-declares-modes.md)).
3. Select one ([0013](0013-selection.md)).
4. Confer what was afforded, and realize the account.

The affordances are applied **after** selection and independently of it: a terminal-mode user can be
afforded `sudo`, and a gui-mode user afforded nothing.

## There is no user-side half to intersect with

Which powers an account holds is the host's decision alone, taken at the site that already names the
person. A bind that affords `containers` and `sudo` confers exactly those; one that affords neither
confers neither — on the same user, from the same source. See
[0010](0010-user-declares-session-shapes.md) for why the user-side ask was removed rather than
narrowed.

## Consequences

- **Per-user differentiation needs no second mechanism.** Two binds on one machine, two affordance
  sets, two accounts, while the machine capability is stated once and applies to both.
- **A users repo can rename or reshape its internals** without breaking a consumer, because the
  consumer names none of them.
- **A host repo is small.** What remains is genuinely host policy: which modes, which people, what
  each may do, and the display and greeter bindings.

## Considered alternatives

- **A per-user grant matrix written out by the host** — rejected as the default: it is the
  hand-written table the turnkey bind exists to remove. Per-person differentiation belongs beside
  the person, not in a table.
- **Keep `usersFlake` and require a flake** — rejected: it names the type, constrains the input for
  no reason, and reads as though the argument were about flakes rather than about publication.
- **A separate call to opt a user out of the default source** — rejected: an override on the entry
  is one fact in one place, where a second call is two that must agree.
