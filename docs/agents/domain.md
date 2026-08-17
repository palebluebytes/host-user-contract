# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This is a **single-context** repo: one `CONTEXT.md` + `docs/adr/` at the root.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root — the domain glossary.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.
  [`docs/adr/README.md`](../adr/README.md) is the authoritative index: a one-line decision per
  ADR, marking which are superseded. Start there rather than guessing at numbers; it names the
  reading order (`0001` the contract, then `0004` why it's this repo, then `0006`/`0007`/`0008`
  the greeter + user-flake shape).

Later ADRs supersede and amend earlier ones — check the index for a supersedes note before
treating an ADR as current.

## File structure

```
/
├── CONTEXT.md                         ← the glossary
├── docs/adr/
│   ├── README.md                      ← the index; start here
│   └── NNNN-*.md                      ← one file per decision
└── *.nix
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids — it calls these out under **Terms to keep distinct**.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/grill-with-docs`, which resolves terms and decisions into these files lazily).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0001 (host↔user contract) — but worth reopening because…_
