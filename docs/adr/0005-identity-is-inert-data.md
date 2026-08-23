# Identity is inert data, authenticated before any code runs

**Status:** Accepted (2026-08-20). The ordering the greeter rests on; serves
[0004](0004-user-is-self-contained.md).

A greeter takes a stranger's flake URL and must decide whether the person in front of it may log
in. The decision has to happen **before** any of that repo's Nix is evaluated, because

> **Nix evaluation is not a sandbox.**

Evaluating a module runs every module body: import-from-derivation, arbitrary `builtins.fetch*`,
non-termination. Authenticating *after* evaluation means running a stranger's code to decide whether
they are allowed to run code.

## Decision

**A user's identity is a JSON file, `identity.json`, read with `jq` before any Nix runs.**

```
name · email · username        required
gmail · hashedPassword · sshKey · trustedKeys    optional
```

The greeter's ordering is the decision in one list:

1. **Fetch the source and its whole input closure** — `nix flake archive`, no flake *output*
   evaluated, so no user Nix has run.
2. **Authenticate eval-free** — `jq` the identity, re-hash the typed password with libc `crypt`,
   and for a trusted tier verify the tree signature ([0019](0019-host-is-the-trust-anchor.md)).
3. **Only then** evaluate anything the user wrote.

Data, not Nix, purely because of *when it is consumed*: identity is read pre-auth and must be inert;
everything else is read post-auth, when the seat has already decided to evaluate.

## One loader, one resolution site, one value

The identity is read **once** on the Nix side and the same value reaches both the system account and
the home. It was briefly split — the home loading its own file while the binding loaded it for the
account — which let a realized account and its home disagree about who the user is.

The rule tightened twice more as the repo grew. `loadIdentity` fixed *who parses*; `mkMembers` then
fixed *who resolves the path*, because the layout rule had been transcribed independently by the
producer's directory scan, the producer coin and the home builder, so one file was read two or three
times per evaluation by three owners. The rule now reads: **one loader, one resolution site, one
value to every consumer.**

The rule is load-bearing for a second reason, discovered later and recorded below: it is the only
thing standing between the two identity surfaces and the merge semantics of the module system. The
greeter provisions the account from the *file* — `bind.nix` hands `identity.json` to provision,
which runs `accountPlan` over it — while the home is built by *evaluating* the user's flake. Those
two reads agree only because neither of them is a declared option. Make identity an option and the
home takes the merged value while the account takes the parsed one, which is the original
account-and-home disagreement restored in a form no loader can fix.

## Why identity cannot be a declared Nix option

The consolidation this record rejects is perennial, so the rejection is written out in full rather
than left as an appeal to the ordering above. It fails twice, on grounds with different lifetimes.

**Declared** here means *declared by the user* — an option in the tree the greeter must read before
it has authenticated anybody. That is the transport, and it is the whole subject below. A produced
home's `contract.identity` ([0026](0026-one-option-prefix-per-party.md)) is not that and is not in
question: it is injected by the contract *after* the decision, `readOnly`, with no author to merge
with. The home **holds** its identity — it neither loads it nor authors it.

### The structural failure: a declared option has no single definition site

> **A declared option's value is the result of merging every module in the user's tree. Merging is
> evaluation. The greeter reads one file before evaluating anything.**

So an identity option cannot be read ahead of evaluation and trusted. A file that is perfectly
literal, imports nothing, and would satisfy any subset restriction —

```nix
{ contract.identity.username = "ada"; }
```

— parses eval-free to `"ada"` and evaluates to `"root"` the moment any second file in the tree says
`lib.mkForce "root"`. The greeter would authenticate one person and realize another. This is a
property of the module system, not a construct that can be banned: `imports` is one channel into it,
and forbidding `imports` closes none of the others.

The obvious repair — assert at eval time that `contract.identity.*` is defined in one file and
nowhere else — was tried against the option types actually in use here and **fails against exactly
the case it is for**:

- `definitionsWithLocations` reports only the **winning priority class**, so an honest `mkForce`
  elsewhere erases `identity.nix` from the list rather than appearing beside it.
- **`_file` is author-controlled.** A module that sets `_file` to the identity file's path has its
  definitions attributed there. The assertion then sees one definition site, in the right file, and
  passes — while the value is `"root"`. A defence that holds against accidents and fails against
  intent is worse than none, because it is trusted.
- **`trustedKeys` needs no trick at all.** It is `listOf str`, and list options merge by
  **concatenation** across files at equal priority — no conflict, no error, no priority games. A
  second file appends an attacker's key to a credential field silently. Scalars at least collide
  loudly; lists do not.

Detecting the disagreement after the fact was considered and is not enough. [0006](0006-identity-describes-a-person.md)
already settled that question for this repo: the group clamp was a correct check that still lost to
deleting the input, because a check passes everything it does not name. **The bar here is that the
values cannot disagree, not that disagreement is noticed.**

### The contingent failure: reading Nix without evaluating it

Reading is permitted; evaluating is not, and **sandboxing a general-purpose evaluator is not the
target** — a bounded evaluator is still an evaluator, and the guarantee drops from structural
("this cannot execute user code") to behavioural ("it can, but the limits are set right"). Against
`jq`, which has no evaluator to bound, that is a straight downgrade.

`nix-instantiate --parse` genuinely does not execute — a file containing `import <nixpkgs> {}` and a
`builtins.trace` parses with no trace fired and no fetch — but it emits canonical Nix syntax, not
data; `--parse --json` is silently ignored and exits 0, so a caller cannot even detect the no-op.
Of the surveyed alternatives, Lix emits a real JSON AST but ships a pre-auth amplification bug,
`nixpkgs-fmt` is archived upstream and exits 0 on syntax errors, and every remaining candidate puts
an evaluator-capable binary on the pre-auth path.

**This half is contingent — the tooling could improve — and it changes nothing**, because a perfect
parser still returns a value the module system is free to disagree with. It is recorded as
corroboration, never as the reason, so that better tooling is not mistaken for a reopened question.

### The strongest surviving form, and why it is still not worth it

There is one shape that clears the structural bar honestly: keep identity injected rather than
declared, and make the post-auth read an `evalModules` over **exactly one module**, with the
contract owning the invocation so the user's tree cannot contribute to it. Merging is then bounded
to one file structurally rather than by assertion, `_file` attribution is irrelevant because nothing
checks it, and `imports` is a literal attrset key a parser can reject before authenticating.

It still needs the pre-auth parser, and it buys nothing:

- **Types at the boundary already exist.** `identity-json.nix` *derives* the schema from
  `identity.nix`'s option set — `required` and `optional` are projections of the option
  declarations — so there is no second field list to delete and a rename in the single identity
  source is already a loud build error.
- **The machinery would grow.** The required-and-unknown typo-net stays, and a parser and a
  legal-subset checker join it on the pre-auth path.

So the trade on offer is `jq` for an evaluator-capable binary, in exchange for authoring four
literal fields in Nix instead of JSON — the authoring win this record already priced as too small.
**The consolidation loses on value, not merely on mechanism.** That is the more durable half of the
rejection: even if every tooling obstacle were fixed tomorrow, there would be nothing to gain.

## Consequences

- **The contract owns the `identity.json` convention** — its filename and its schema — and exposes
  both (`identityFile`, `identitySchema`) so a greeter can introspect the shape it authenticates
  against.
- **The loader is a typo-net.** A missing required field or an unknown key is a loud error, not a
  silently-wrong account.
- **The home *holds* its identity — it neither loads it nor authors it.** Identity-driven dotfiles
  read `config.contract.identity.name` ([0026](0026-one-option-prefix-per-party.md)); nothing in a
  home reads a file, and nothing in a home may redefine one.

## Considered alternatives

- **Identity in Nix, under `contract.*` with everything else** — the perennial proposal, explored
  properly and rejected on two independent grounds; the full reasoning is *Why identity cannot be a
  declared Nix option* above. In short: as a **declared option** it is impossible, because the
  option's value is whatever the whole tree merges to and the greeter reads one file before
  evaluating anything; as a **literal file** it is merely pointless, because the win is already
  banked. An earlier version of this record claimed the change would delete the JSON schema
  projection and the loader. **That was wrong** — the projection is what makes the schema derive
  from `identity.nix` rather than duplicate it, and the loader's typo-net survives any transport.
  Machinery would grow.

  **Not to be confused with the option of the same name.** A produced home holds its identity at
  `contract.identity` ([0026](0026-one-option-prefix-per-party.md)) — the same word, the opposite
  direction. What this bullet rejects is identity **authored by the user** as the pre-auth
  transport, where the value is whatever the whole tree merges to and the greeter has decided
  nothing yet. What a home has is identity **injected by the contract** post-auth and `readOnly`,
  which is this record's own *one loader, one resolution site, one value* arriving at its last
  consumer rather than a second definition of it.
- **Author in Nix, generate `identity.json`** — the middle ground, and it does not quite work: a
  greeter reads the fetched *source tree*, and reaching a flake output means evaluating the flake.
  The generated file would have to be committed with a drift check — a build artifact in git, for an
  authoring win of four literal fields. Recorded because it is the obvious next proposal. It was
  held open as the fallback while the option route was investigated, and never reached: the route
  failed on grounds that leave the authoring win as the only thing still on offer, which is what
  this bullet already declines.
- **Split the file — credentials inert, descriptive fields in Nix** — rejected: the line is
  defensible but it gives one concept two homes and two vocabularies, against
  [0006](0006-identity-describes-a-person.md)'s reading of an identity as one description of one
  person. The `trustedKeys` merge above sharpens the case rather than reopening it: the credential
  half would have to stay inert data regardless, so the split buys only the authoring win on
  `name`, `email` and `gmail` — and leaves those free to be forced by any module in the tree.
