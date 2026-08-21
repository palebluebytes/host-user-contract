# Reading `contract.identity.*` out of a Nix module without evaluating it

Research for [#75](https://github.com/palebluebytes/host-user-contract/issues/75), under map
[#74](https://github.com/palebluebytes/host-user-contract/issues/74).

**Question.** `nix-instantiate --parse` provably does not execute, but on Nix 2.34.8 it emits
canonical Nix syntax rather than JSON. What should read that output — or what should replace
the approach?

**This document does not pick a winner.** That decision belongs to the spike, [#78](https://github.com/palebluebytes/host-user-contract/issues/78).

Every claim was verified by running the command shown, on this machine, on 2026-08-21, unless
explicitly marked *unverified*. Environment: NixOS, CppNix 2.34.8, nixpkgs pinned in
`flake.lock` at `567a49d1913ce81ac6e9582e3553dd90a955875f`.

---

## Summary

| Candidate | AST as data? | Marginal closure | Code between file and value | Verdict-shaping fact |
| --- | --- | --- | --- | --- |
| **Lix ≥ 2.93** `nix-instantiate --parse` | **JSON, merged attrpaths** | +191.6 MiB (`pkgs.lix`) | **5 lines of jq** | **Quadratic output blow-up: a 40 KB file emits >4 GB** |
| CppNix `--parse` + hand-written reader | canonical Nix syntax | +157.3 MiB (`pkgs.nix`) | **104 lines of Perl** | Depends on undocumented printer invariants |
| `nixpkgs-fmt --parse --output-format json` | JSON CST, **unmerged** | +13 MB | jq + your own attrpath merge | Upstream **archived** 2024-07; exits 0 on syntax errors |
| tree-sitter-nix | s-expr / XML, **no JSON** | +20.1 MiB | driver you write (~28 py / ~45 C) | Error recovery yields *confidently wrong* trees |
| rnix-parser (statix) | **no** | +49.6 MiB | a Rust crate you package | "already paid for" is **false** — statix is dev-shell only |
| hnix | **no** — `--json` unimplemented | +4.62 **GB** | n/a | Dead on arrival |
| nixel | Rust `Debug` only | +50.3 MiB | bespoke parser | Unmaintained since 2022; parser diverges from CppNix |
| nil / nixd / nixfmt / deadnix / alejandra | no AST-as-data | — | — | Output explicitly disclaimed as human-only, or lint-only |
| CppNix ≥ 2.35 / any future CppNix | **no, and none planned** | — | — | Feature attempted twice, abandoned twice |

---

## Headline: four findings that bear on the map's premise

1. **A parse-only reader and the module system disagree, and no parser choice fixes it.**
   `imports` is resolved by the module system, not by the parser. A module that parses to
   `{ contract.identity.name = "ada"; }` can *evaluate* to a different `username` and
   `hashedPassword`, pulled from an imported file the parser never opens. Demonstrated below.
   Map #74's destination requires that the extracted value "cannot disagree with what the
   module system sees from the same file"; that property is obtainable only by *forbidding*
   `imports` and having the extractor reject it. See [Finding A](#finding-a-imports-breaks-agreement).

2. **Every viable candidate puts an evaluator-capable binary on the pre-auth path.** Today's
   pre-auth surface (`jq`, `perl`, `openssh`) contains nothing that can evaluate Nix at all.
   Both leading candidates add a binary whose *other* mode is `--eval`, invoked pre-auth on
   attacker-controlled input. The flag is proven inert; the *category* of the dependency
   changes. Only tree-sitter and nixpkgs-fmt are structurally incapable of evaluation.
   See [Finding B](#finding-b-the-pre-auth-dependency-changes-category).

3. **Lix ≥ 2.93 solves the stated question — the extractor really is ~5 lines of jq — but it
   ships a pre-auth denial-of-service.** Lix serialises the AST with two-space indentation and
   no way to turn it off, making output size **quadratic in nesting depth**. A 40 KB hostile
   file produced **over 4 GB** and was still writing when killed at 60 s. See
   [Candidate 4](#candidate-4-lix--293--the-only-real-json-ast).

4. **`--parse --json` on CppNix is not a version gap to wait out.** The documented CLI grammar
   excludes the combination, the source short-circuits before the output-format flag is read,
   and the feature was attempted and abandoned twice upstream (PRs #4731, #5512), with the
   tracking issue #4726 open since 2021.

---

## The baseline being replaced

`greeter/auth.nix` extracts two fields pre-auth:

```sh
claimed=$(jq -r '.username // empty' "$identity")
stored=$(jq -r '.hashedPassword // empty' "$identity")
```

**Two lines** of project-owned code, over a format with a published grammar (RFC 8259),
through a binary whose only job is reading that format.

Candidates are measured against those two lines, not against jq's C source. Closures:

```console
$ nix path-info -S -h nixpkgs#jq nixpkgs#perl nixpkgs#openssh nixpkgs#nix nixpkgs#statix nixpkgs#lix
/nix/store/1bp02949k0xdihbgphpwbzba1741pknk-jq-1.8.2-bin                       37.1 MiB
/nix/store/cc9zsahxyx5my7bqid4dzkljw2dd9ygm-perl-5.42.0                       104.0 MiB
/nix/store/71zy9jmcszcfmmn4zf68sm8vywryybhp-openssh-10.3p1                     78.8 MiB
/nix/store/iirndnicd13h4zjr8xwwj8hq2cghpfjn-nix-2.34.8                        157.3 MiB
/nix/store/fldbgayi8ph4wrzx90nxn3pqrhd8a5wg-statix-0.5.8-unstable-2026-07-10    49.6 MiB
/nix/store/zmg5ayp5qpin0v4y6hfg684kvixldq0x-lix-2.95.2                        191.6 MiB
```

`perl` and `openssh` are already in the same `runtimeInputs` list, so anything written in Perl
adds **zero** closure. Standalone closure numbers overstate marginal cost (everything shares
glibc); marginal figures measured inside a real `writeShellApplication` are given per candidate.

---

## What CppNix `--parse` actually emits

### Confirmed: `--json` is silently ignored, on 2.34.8 *and* 2.35.1

```console
$ nix-instantiate --parse --json identity.nix
{ contract = { identity = { email = "ada@example.com"; … }; }; }
$ echo $?
0
```

Byte-identical with and without `--json`. Exit 0 — no warning, no error, so a caller **cannot
detect the no-op from the exit code**. Same on `nixVersions.latest` (2.35.1), where
`--parse --xml` is likewise ignored.

Source, `src/nix/nix-instantiate/nix-instantiate.cc` on CppNix `master`:

```cpp
if (parseOnly) {
    e->show(state.symbols, std::cout);
    std::cout << "\n";
    return;
}
```

The short-circuit precedes any use of `OutputKind`. Argument parsing *does* accept `--json`
(setting `outputKind = okJSON`), which is exactly why it is swallowed rather than rejected.
`src/libexpr/include/nix/expr/nixexpr.hh` contains zero occurrences of `json`/`toJSON`; the
only dump is `virtual void show(const SymbolTable &, std::ostream &)`. libexpr ships
`value-to-json.hh` and `value-to-xml.hh` — both **Value**, i.e. post-eval — and
`json-to-value.hh` (the inverse, backing `builtins.fromJSON`). There is no `expr-to-json.hh`.

The manual agrees:

```console
$ man 1 nix-instantiate
nix-instantiate [--parse | --eval [--strict] [--raw | --json | --xml]] …
```

`--json` is scoped to `--eval`. `--parse` is documented in one sentence — *"Just parse the
input files, and print their abstract syntax trees on standard output as a Nix expression"* —
with **no format-stability guarantee**.

### Upstream history

| # | Title | State |
| --- | --- | --- |
| [4726](https://github.com/NixOS/nix/issues/4726) | feature: parse nix expression to json ast | **OPEN** since 2021-04-21 |
| [4731](https://github.com/NixOS/nix/pull/4731) | nix-instantiate: parse to json ast | **CLOSED unmerged** 2021-11-07 |
| [5512](https://github.com/NixOS/nix/pull/5512) | nix parse: … to aterm or json syntax tree | **CLOSED unmerged** 2024-03-09 |
| [11124](https://github.com/NixOS/nix/issues/11124) | More explicit parser dump format for testing | **OPEN** since 2024-07-17 |
| [1368](https://github.com/NixOS/nix/issues/1368) | `--xml` has no effect with `--parse` | **CLOSED** 2017 — resolved as a *docs* bug: *"the xml and json conversions only apply to values"* |
| [1375](https://github.com/NixOS/nix/issues/1375) | `--parse` does more than parsing | **CLOSED / NOT_PLANNED** 2026-08-13 |

Release notes through `rl-2.35.md` and the unreleased `rl-next/` contain nothing AST-related.
Neither Nix 2.35.1 (117 builtins) nor Lix 2.95.2 (113) has a `parseExpr`-style builtin; the
only `parse*` entries are `parseDrvName` and `parseFlakeRef`.

### The canonical form, precisely

Input:

```nix
{
  contract.identity.name = "ada";
  contract.identity.sshKey = "ssh-ed25519 AAAAC3Nz ada@host";
  contract.identity = {
    hashedPassword = "$y$j9T$abc$def";
    trustedKeys = [ "ssh-ed25519 AAAAC3Nz k1" "ssh-rsa AAAAB3Nz k2" ];
  };
}
```

Output (one line, wrapped here):

```
{ contract = { identity = { email = "…"; gmail = "…"; hashedPassword = "$y$j9T$abc$def";
  name = "ada"; sshKey = "ssh-ed25519 AAAAC3Nz ada@host";
  trustedKeys = [ ("ssh-ed25519 AAAAC3Nz k1") ("ssh-rsa AAAAB3Nz k2") ]; username = "ada"; }; }; }
```

| Property | Verified behaviour |
| --- | --- |
| Dotted paths | Canonicalised into nested attrsets; a separate `contract.identity = { … }` block merges in |
| Attribute order | Sorted by attribute name |
| Output shape | A **single line**, always — newlines inside strings are escaped |
| Comments | Stripped |
| Source parens | **Dropped** — 50 000 nested parens around `"x"` produced 13 bytes of output |
| List elements | **Always** re-wrapped in parens: `[ ("a") ("b") ]` |
| Relative paths | Resolved to absolute against the source dir, and leaked into the output |
| `~/foo` | Expanded from `$HOME` — parse-time impurity |
| `<nixpkgs>` | Printed as `(__findFile __nixPath "nixpkgs")`; the path is **not** searched |
| `imports` | Printed as a path literal; the file is **not opened** (a fixture importing a nonexistent `./other.nix` still parses) |
| Numeric normalisation | `1.5e3`→`1500`; `-1`→`(__sub 0 1)`; `1 < 2`→`(__lessThan 1 2)`; `3 >= 4`→`(! (__lessThan 3 4))` |
| Indented strings | `''…''` desugars to a `+` chain of ordinary strings |
| String escapes emitted | `\"` `\\` `\n` `\r` `\t` `\${` — and **nothing else** |
| Free variables | **Rejected**: `{ x = pkgs.hello; }` → `error: undefined variable 'pkgs'`. `--parse` runs static binding analysis (this is [#1375](https://github.com/NixOS/nix/issues/1375), closed NOT_PLANNED) |

### Escaping is complete for delimiters; raw control bytes are not

`"` and `\` are *always* escaped, so the two-character sequence `= "` can only occur at a real
syntax position. That is the invariant any reader depends on — discovered by experiment, not
promised by the manual.

Control characters other than TAB/LF/CR pass through **raw**:

```console
$ nix-instantiate --parse ctrl.nix | cat -v
{ k = "^A^B^C^D^E^F^G^H\t\n^K^L\r^N^O^P^Q^R^S^T^U^V^W^X^Y^Z^[^\^]^^^_…"; }
```

`^[` (ESC) reaches the output unescaped — a terminal-escape injection vector for anything that
echoes an extracted field pre-auth. Today's `jq -r` has the same property, so this is not a
regression, but neither is it fixed by the change.

A raw CR byte in source is normalised to LF by the lexer (`"a<CR>b"` prints `"a\nb"`); the
escape `\r` survives as `\r`.

A NUL byte in a string literal makes the **printer** refuse, fail-closed:

```console
$ nix-instantiate --parse nul.nix; echo "EXIT=$?"
error: input string 'before␀after' cannot be represented as Nix string because it contains null bytes
EXIT=1
```

### Robustness of CppNix `--parse` on hostile input

| Fixture | Size | Result |
| --- | --- | --- |
| 400 000 nested lists | 800 KB | exit 0, parsed |
| 1 000 000 nested lists | 2.0 MB | **exit 1**, `error: stack overflow (possible infinite recursion)`, 243 MB peak RSS, 0.77 s |
| 1 000 000 nested attrsets | 9.0 MB | **exit 1**, same clean error, 438 MB peak RSS, 1.63 s |
| 400 000 flat attrs | 18.3 MB | exit 0, 17.5 MB output, 163 MB peak RSS, 2.17 s |
| unterminated string | — | **exit 1**, `syntax error, unexpected end of file, expecting '"'` |

Nix's own recursion guard catches the deep cases and **fails closed with a diagnostic, not a
segfault**. Output size is linear in input size. This is a genuinely good result.

Two cost notes. An 18 MB input produced 17 MB of output at ~163 MB RSS — ~9× the input in
memory, and the reader then consumes 17 MB. And Nix's error messages **echo the offending
source line**, so a 5 MB single-line unterminated string produces a 5 MB stderr dump. Both are
mitigable with an input-size cap, but the cap becomes part of the security argument.

---

## Finding A: `imports` breaks agreement

Map #74's destination requires that the extracted value "cannot disagree with what the module
system sees from the same file". It can.

`mod-main.nix`:

```nix
{
  imports = [ ./mod-extra.nix ];
  contract.identity.name = "ada";
}
```

`mod-extra.nix`:

```nix
{
  contract.identity.username = "root";
  contract.identity.hashedPassword = "$y$attacker-controlled";
}
```

What the module system sees:

```console
$ nix-instantiate --eval --strict --json eval-module.nix
{"hashedPassword":"$y$attacker-controlled","name":"ada","username":"root"}
```

What any parse-only reader sees:

```console
$ nix-instantiate --parse mod-main.nix
{ contract = { identity = { name = "ada"; }; }; imports = [ (/…/mod-extra.nix) ]; }
$ nix-instantiate --parse mod-main.nix | perl read-canonical.pl contract.identity.username
reader: 'contract.identity.username' not found
```

The pre-auth reader reports "no username"; the post-auth module system provisions `root` with
an attacker-chosen password hash.

**This is parser-independent.** Every candidate reads one file. The resolutions are:

- **Forbid `imports`** in the identity module, and have the extractor *reject* any module
  containing one — a hard, testable rule (the jq filter in
  [Candidate 4](#candidate-4-lix--293--the-only-real-json-ast) implements it in one clause); or
- **Follow imports transitively** pre-auth, which means resolving paths, handling non-literal
  `imports` entries, and re-implementing module merge order — i.e. exactly the "bad
  re-implementation of the module system" the map wants to delete, moved from the JSON side to
  the Nix side.

The same argument extends to `disabledModules` and anything else that changes the file set.

### Correction to a fact recorded in #74

#74 records: *"A function module does not [canonicalize] — `{ config, lib, ... }: { … }` stays
a lambda, opaque without eval."* The body is **not** opaque:

```console
$ nix-instantiate --parse fnmod.nix
({ config, lib, ... }: { contract = { identity = { hashedPassword = "$y$real"; username = "ada"; }; }; })
```

The whole body is plainly readable. The accurate statement is that it is **readable but not
sound to read** — its values may depend on arguments the module system will supply. The
practical conclusion (constrain identity to a bare attrset) is unchanged; the reason is
different, and every extractor must **deliberately reject** lambdas rather than failing
incidentally.

---

## Finding B: the pre-auth dependency changes category

`greeter/auth.nix` currently runs `jq`, `perl` and `openssh` before a password is checked. None
can evaluate Nix.

Both leading candidates change that:

- **CppNix `--parse`** requires `pkgs.nix` (157.3 MiB). `nix-instantiate` is *the evaluator*;
  `--parse` and `--eval` are the same binary, one flag apart.
- **Lix `--parse`** requires `pkgs.lix` (191.6 MiB), with the same property.

`--parse` is proven inert — re-verified here on a file combining `builtins.fetchurl`,
`import <nixpkgs> {}`, `builtins.trace "EXECUTED-TRACE"`, `builtins.readFile /etc/shadow` and
an infinite recursion:

```console
$ nix-instantiate --parse evil2.nix   # Lix 2.95.2
rc=0  stdout_bytes=3647
trace fired? 0 occurrences on stderr
shadow leaked? 0
```

No trace, no fetch, no read, no hang. The AST *contains* the string `EXECUTED-TRACE` as an
`ExprLiteral` — data, not execution.

So the risk is not that `--parse` evaluates. It is that a mis-set flag, a wrapper change, or a
future refactor in a 150–190 MiB evaluator now sits inside the authentication boundary, where
the reviewer's guarantee used to be structural ("nothing here *can* evaluate") and would become
behavioural ("this flag doesn't"). tree-sitter and nixpkgs-fmt keep the structural guarantee.

---

## Candidate 1 — tree-sitter-nix

**Attributes.** There is no top-level `pkgs.tree-sitter-nix`.

| What | Attribute | Version |
| --- | --- | --- |
| CLI + `libtree-sitter` | `pkgs.tree-sitter` | 0.26.9 |
| Nix grammar (compiled `.so`) | `pkgs.tree-sitter-grammars.tree-sitter-nix` | `0.3.0-unstable-2025-12-03` |
| Python binding | `pkgs.python3Packages.tree-sitter` | 0.25.2 |

**Marginal closure, measured inside a real `writeShellApplication`: +20.1 MiB** over a jq-only
app (12 MiB tree-sitter binary, 9.9 MiB `gcc-lib` — the Nix grammar's external scanner is C++,
so `parser` links `libstdc++`, unavoidably).

**It can join `runtimeInputs`, with a wrinkle.** The nixpkgs grammar ships only the compiled
`parser` — no `src/grammar.json` — so the CLI's normal `parser-directories` discovery **fails**:
`Failed to load language for path "foo.nix" … .../src/grammar.json: No such file or directory`.
The route that works needs no config, no `HOME`, no compiler:

```nix
pkgs.writeShellApplication {
  name = "nix-ast";
  runtimeInputs = [ pkgs.tree-sitter ];
  text = ''
    exec tree-sitter parse \
      --lib-path ${pkgs.tree-sitter-grammars.tree-sitter-nix}/parser \
      --lang-name nix \
      "$@"
  '';
}
```

`--lang-name nix` is mandatory (otherwise the symbol is derived from the filename and `dlsym`
fails). The grammar cannot go in `runtimeInputs` — it has no `bin/` — so it must be
interpolated, which is what puts it in the closure.

**Output format: s-expression (default), `-x` XML, `--dot`, `-c` CST. No JSON AST.** `--json`
is a deprecated alias for `--json-summary`, which emits only per-file success/duration/bytes.
The s-expression carries byte ranges but **not the source text**, so extraction means
range-slicing the original file — or using `tree-sitter query`, which does emit capture text
directly and is the better interface. Attrpaths appear as sibling `identifier` nodes under one
`attrpath`, which is the right shape; but tree-sitter does **no attrpath merging**, so
`contract.identity.name = …` and `contract.identity = { … }` remain separate and must be merged
by the consumer.

**Robustness — three real hazards.**

1. **Error recovery produces confidently wrong trees.** For `a = "never closed;` tree-sitter
   silently reinterprets the string as code — `never closed` becomes a function application —
   and buries one `(ERROR …)` node in the output. Nix refuses outright. **Any consumer must
   check the exit code or scan for `ERROR` nodes**, or it will act on a plausible misparse.
2. **The printer is O(depth²)** — each level adds two spaces of indentation. Printing a
   500 000-deep tree took **325 s** versus 3.26 s at 50 000 (exactly 100× for 10× depth). The
   `-x` XML variant did not finish in 600 s. `-q` (parse only, exit code) and
   `tree-sitter query` are immune.
3. **`--timeout` does not bound the printer.** `--timeout 500000` (0.5 s) on a 50 000-deep file
   still ran the full 3.34 s and exited 0. It does bound *parsing*: `--timeout 1000` on a 20 MB
   file exits 1 — **silently, with no stderr message**.

The parser itself never stack-overflowed or segfaulted (it is iterative): 500 000 nested `[`
in 1.25 s / 181 MB; 20 MB of assignments in 4.12 s / 424 MB. A naive **recursive** consumer is
the trap — a Python walker hit `RecursionError` on a tree that parsed fine; in C that is a
segfault. An iterative `TSTreeCursor` walk handled 500 000 depth in 1.34 s.

**Two operational annoyances.** `Warning: You have not configured any parser directories!` is
printed on every invocation and could not be suppressed by any means tried (stderr-only, so
`2>/dev/null` keeps stdout clean). The per-file `… Parse: 1.97 ms …` summary goes to **stdout**,
mixed in after the AST, and `-q` does not suppress it.

**Code between file and value:** a driver you write. ~28 lines of Python (closure 226.9 MiB) or
~45 lines of C (same 57.1 MiB as the CLI) — both verified working — or shell + `tree-sitter
query` + text munging, plus your own attrpath merge either way.

## Candidate 2 — rnix-parser / statix

### The "already paid for" premise is false

`statix` appears in this repo exactly once, in the **dev shell**:

```console
$ grep -rn "statix" --include=*.nix .
flake.nix:234:      # … linting (statix/deadnix for Nix, ruff for Python, shellcheck for shell) …
flake.nix:249:              p.statix
```

It is a `nix develop` input. It is **not** in any package's `runtimeInputs`, so it is not in any
host's system closure. Putting an rnix-based tool on the greeter's pre-auth path is a **new**
49.6 MiB runtime dependency shipped to every host, not reuse of an existing one.

### statix cannot dump an AST

```console
$ nix shell nixpkgs#statix -c statix --help
Commands:
  check    Lints and suggestions for the nix programming language
  …
  dump     Dump a sample config to stdout
```

`dump` is a red herring — it prints a sample `statix.toml`:

```console
$ nix shell nixpkgs#statix -c statix dump
disabled = []
ignore = [".direnv"]
```

`statix check --format json` emits **lint diagnostics**, not a syntax tree. Same for `deadnix
-o json` (49.9 MiB): `{"file":"…","results":[{"column":17,"line":3,"message":"Unused let
binding: mkIf"}]}`.

There is no `rnix` package in nixpkgs:

```console
$ nix search nixpkgs --json rnix
{"legacyPackages.x86_64-linux.kubernix":…,"legacyPackages.x86_64-linux.vscode-extensions.rebornix.ruby":…}
```

rnix-parser is a **library crate only**. Using it directly means writing and packaging a Rust
binary — a new `buildRustPackage`, a `Cargo.lock` to review and vendor, and a new language
toolchain in a repo that is currently Nix + shell + a little Python. The extractor code would be
short; the *packaging* is the cost, and every host bears it.

**But rnix is reachable without any of that** — see `nixpkgs-fmt` under
[Candidate 5](#candidate-5-others).

## Candidate 3 — a strict reader over the canonical output

The only candidate with **zero new closure for the reader itself**: `perl` is already in
`greeter/auth.nix`'s `runtimeInputs`. It still requires adding `pkgs.nix` (157.3 MiB) — see
[Finding B](#finding-b-the-pre-auth-dependency-changes-category).

### A working prototype exists

`read-canonical.pl` (see [appendix](#appendix-fixtures-and-prototype)) implements a
literal-only reader:

- **tokeniser** — strings with the six escapes above, identifiers, `{}[]()=;`, everything else
  as one opaque token;
- **`skip_value`** — an iterative, brace-balanced skip over non-target bindings, so unrelated
  option namespaces (`contract.cli.enable = true;`, `imports = [ … ];`) do not force a reject;
- **`literal`** — accepts **only** string, list-of-literal, and the printer's parens; rejects
  everything else;
- caps: depth 64, input 1 MB.

**104 non-blank, non-comment lines; 130 with comments.** Against a two-line `jq` baseline, ~50×.

### It survives the attacks

| Fixture | Path | Result |
| --- | --- | --- |
| `identity.nix` | `…username` / `…hashedPassword` | `ada` / `$y$j9T$abc$def` |
| `identity.nix` | `…trustedKeys` | both keys, in order |
| `hostile.nix` | `…name` | round-trips `"` `;` `}` `]` `\` `${` TAB LF exactly |
| `hostile.nix` | `…sshKey` (`"prefix" + "suffix"`) | **reject** |
| `hostile.nix` | `…email` (indented `''…''`) | **reject** |
| `hostile.nix` | `…gmail` (`let … in`) | **reject** — `value is not a literal (found 'let')` |
| `hostile.nix` | `…hashedPassword` (`builtins.readFile`) | **reject** |
| `spoof.nix` | `…name` (`"a${""}b"`) | **reject** |
| `spoof.nix` | `…gmail` (`if … then …`) | **reject** |
| `sortattack.nix` | `…username` | `ada` — the decoy key sorts first and is correctly treated as a key |
| `desync.nix` | `…username` | `ada` — a key ending in `\\` does not desync the string scanner |
| `scalars.nix` | `a` (`true`), `c` (`1`) | **reject** — non-string scalars are outside the literal subset |
| `fnmod.nix` | `…username` | **reject** — lambda module |
| `deep.nix` / `big.nix` | — | **reject** — depth cap / size cap |

### The attacks it had to survive, spelled out

Real properties of the canonical format, not hypotheticals:

- **Attribute names are an arbitrary escaped-string alphabet.**
  `contract.identity."aaa; username = \"root\"; hashedPassword = \"\"; z" = "decoy";` is legal
  Nix, prints as a key containing what looks like two whole bindings, **and sorts before the
  real `username`**. A regex-based extractor is not viable.
- **Backslash desync.** A key ending in `\\` (printed `"aaa\\"`) breaks any scanner that treats
  "previous char was `\`" as "this quote is escaped" without also consuming `\\`.
- **Literal-looking non-literals.** `sshKey = "prefix" + "suffix"` prints as
  `("prefix" + "suffix")`. A reader grabbing the first quoted token after `sshKey = ` extracts
  `prefix` while the module system evaluates `prefixsuffix` — silent disagreement on a
  security-relevant field.
- **Indented strings desugar to concatenation.** `''…''` becomes a `+` chain, so an idiomatic
  multi-line SSH key must either be rejected — surprising — or the reader must fold `+` over
  string literals, reopening the "is this really a literal?" question the reader exists to close.
  (Lix's JSON AST does **not** have this problem; it folds `''…''` into an `ExprLiteral`.)
- **`true` / `null` are bare identifiers** in the output, indistinguishable from a variable
  reference. Harmless for the seven string/list fields in scope; a landmine if a boolean field
  is added.

### Honest assessment

The prototype is correct against every fixture, and 104 lines of straight-line recursive descent
is not unreadable — a reviewer *can* sit down with it. But:

- It is **~50× the code** of the baseline, and it is a **parser** — the category of program with
  the worst ratio of "looks obviously right" to "is right".
- Its correctness rests on **undocumented invariants** of Nix's expression printer (`"` and `\`
  always escaped; output always one line; parens always around list elements). The manual pins
  nothing. A Nix upgrade that changes the printer changes the pre-auth security boundary
  *silently*, because the reader would keep parsing.
- The pipeline needs an explicit `pipefail` story: a `nix-instantiate` failure (NUL byte, stack
  overflow, syntax error, undefined variable) exits 1 and prints nothing, and a reader fed empty
  input must reject rather than return empty.

## Candidate 4 — Lix ≥ 2.93 — the only real JSON AST

**Lix ≥ 2.93 makes `nix-instantiate --parse` emit a JSON AST unconditionally**, with no
evaluation. Lix 2.93 release note, verbatim:

> `nix-instantiate --parse` does not print out the AST in a Nix-like format anymore. Instead,
> it now prints a JSON representation of the internal expression tree.

Source, `lix/legacy/nix-instantiate.cc`:

```cpp
if (parseOnly) {
    std::cout << e.toJSON(state.ctx.symbols).dump(2);
    std::cout << "\n";
    return;
}
```

Verified here on Lix 2.95.2:

```console
$ nix shell nixpkgs#lix -c nix-instantiate --parse identity.nix
{
  "_type": "ExprSet",
  "attrs": {
    "contract": { "_type": "ExprSet", "attrs": { "identity": { "_type": "ExprSet", "attrs": {
      "hashedPassword": { "_type": "ExprLiteral", "value": "$y$j9T$abc$def", "valueType": "String" },
      "name":           { "_type": "ExprLiteral", "value": "ada", "valueType": "String" },
      "trustedKeys":    { "_type": "ExprList", "elems": [
                            { "_type": "ExprLiteral", "value": "ssh-ed25519 AAAAC3Nz k1", "valueType": "String" },
                            { "_type": "ExprLiteral", "value": "ssh-rsa AAAAB3Nz k2",     "valueType": "String" } ] },
      "username":       { "_type": "ExprLiteral", "value": "ada", "valueType": "String" }
    }, "recursive": false } }, "recursive": false }
  }, "recursive": false
}
```

Crucially it **merges dotted attrpaths with real Nix semantics** — `contract.identity.name = …`
plus a separate `contract.identity = { … }` collapse into one nested tree — which every other
data-emitting candidate leaves to the consumer.

**Availability.** `lix` is top-level in nixpkgs (2.95.2 in the registry), and **Lix 2.94.2 is
present in this repo's pinned nixpkgs** (`567a49d…`). The live attribute set is `lixPackageSets`
(`lixVersions` is deprecated: *"'lixVersions.latest' has been renamed to
'lixPackageSets.latest.lix'"*); 2.90–2.93 are present as attributes but throw *"removed from
this revision of Nixpkgs"*. Closure of 2.95.2: **191.6 MiB**. *(Unverified: the exact closure of
the pinned 2.94.2 — it was not in the local store and I did not build it.)*

### The extractor really is five lines

```jq
# Extract one `contract.identity.<$f>` literal from a Lix `--parse` JSON AST.
def inert: select(._type == "ExprSet" and .recursive == false)
         | select(.attrs | has("imports") | not);
def str:   select(._type == "ExprLiteral" and .valueType == "String").value;
inert | .attrs.contract | inert | .attrs.identity | inert | .attrs[$f]
  | if ._type == "ExprList" then .elems[] | str else str end
```

Every step asserts; anything unasserted yields no output and `jq -e` exits 4. Verified against
the whole fixture set — it matches the 104-line Perl reader's behaviour exactly, and does
*more*:

| Fixture | Behaviour |
| --- | --- |
| `identity.nix` | all seven fields extracted correctly |
| `hostile.nix` `…email` (indented `''…''`) | **accepted** — Lix folds it to an `ExprLiteral` (the canonical reader must reject this) |
| `hostile.nix` `…sshKey` (`"a" + "b"`) | reject |
| `hostile.nix` `…gmail`/`…hashedPassword` (`let`, `builtins.readFile`) | reject |
| `spoof.nix` `…name` (`"a${""}b"`) | reject (`ExprConcatStrings` with `"isInterpolation": true`) |
| `sortattack.nix` / `desync.nix` | correct — JSON keys, so the string-scanner attacks are structurally impossible |
| `fnmod.nix` (lambda module) | reject — root is `ExprLambda` |
| `evil2.nix` (`let … in { … }`) | reject — root is `ExprLet` |
| `rectest.nix` (`rec { … }`) | reject — `recursive: true` |
| `comments.nix` / `mod-main.nix` (have `imports`) | **reject** — the `has("imports")` clause |

That is a **5-line, fully-asserting extractor** against a **2-line** baseline, over JSON rather
than a bespoke syntax. On audit cost alone this is the strongest candidate — arguably *better*
than the baseline, because the assertions are explicit where `jq -r '.username'` has none.

### But: a quadratic pre-auth denial of service

Lix serialises with `.dump(2)` — two-space indentation, depth-proportional, with **no flag to
disable it** (`--parse --json` and `--parse --xml` are byte-identical to bare `--parse`; the
format is unconditional, not flag-selected). Output size is therefore **quadratic in nesting
depth**. Measured, 60-second cap per run, input is `{ a = [[[…]]]; }`:

| depth | input | CppNix 2.34.8 output | Lix 2.95.2 output |
| --- | --- | --- | --- |
| 100 | 210 B | 607 B | 105 KB |
| 1 000 | 2.0 KB | 6 007 B | 10.05 MB |
| 5 000 | 10 KB | 30 007 B | **250.25 MB** |
| 10 000 | 20 KB | 60 007 B | **1.0005 GB** — killed at 60 s, still writing |
| 20 000 | 40 KB | 120 007 B | **4.001 GB** — killed at 60 s, still writing |
| 50 000 | 100 KB | 300 007 B | killed; 0 bytes emitted |

Exactly 25× output for 5× depth. **A 40 KB file from an unauthenticated repo produces over 4 GB
in under a minute, and does not stop.** An earlier run on the 100 KB / 50 000-deep fixture spun
for **over 10 minutes** at ~105 MB RSS with **zero bytes** of output before being killed — so it
is CPU-bound in the serialiser, not merely disk-bound, and the process is not self-limiting.

This is directly weaponisable against the greeter: it happens *before* the password check, from
a file the attacker fully controls, at ~100 000× amplification.

**It is mitigable, but the mitigation is now part of the security argument**: the cap must be
applied to the *output stream* (e.g. piping through a byte limiter and failing closed), because
an input-size cap does not help — 20 KB of input is already over a gigabyte out. A nesting-depth
pre-check would itself need a parser.

### Other Lix caveats, all observed directly

- **The format is explicitly unstable.** Lix's own manual: *"The output format of the AST
  depends on the current internal representation and may change in the future."*
- **No source positions** anywhere in the JSON — no line, column or file. Diagnostics that point
  at a line are impossible.
- **Attrpath spelling, source order and path relativity are lost.** Attrs are emitted sorted by
  symbol; `./relative/thing` becomes an absolute `ExprLiteral` with `"valueType": "Path"`.
- `true`/`false` are `ExprVar`, not literals; comments are not preserved.
- **It also rejects free variables**, exactly as CppNix does — `undefinedVariableThatDoesNotExist`
  errors on both. Not a Lix-specific caveat.
- Adopting it makes the greeter's pre-auth path depend on a **fork of Nix**, tracked separately
  from the CppNix the rest of the system uses.

### CppNix has no path here

Verified on `nixVersions.latest` (2.35.1) and `nixVersions.git` (2.35pre20260619): `--parse
--json` and `--parse --xml` both emit canonical Nix syntax, exit 0, flag silently ignored.
`nix eval` has no `--parse` flag at all (`src/nix/eval.cc` registers only `--raw`, `--apply`,
`--write-to` plus `MixJSON`'s `--json`, and `run()` unconditionally calls `toValue`) — *this
last point is verified from source only; the sandbox blocked running `nix eval` directly*.
`nix __dump-cli` and `nix __dump-language` are gone from 2.35.1.

Available versions: `nixVersions.latest` 2.35.1, `.stable` 2.34.8, `.git` 2.35pre20260619,
`nix_2_4` … `nix_2_35`; `nixVersions.unstable` and `.minimum` throw.

## Candidate 5 — others

### `nixpkgs-fmt --parse --output-format json` — the one nobody listed

```console
$ nix shell nixpkgs#nixpkgs-fmt -c nixpkgs-fmt --help
nixpkgs-fmt 1.3.0
FLAGS:
        --parse      Show syntax tree instead of reformatting
OPTIONS:
        --output-format <FORMAT>    Set output format of --parse [default: rnix]  [possible values: rnix, json]
```

This is **rnix without packaging anything** — a lossless rowan CST as JSON, every token
including whitespace, with `text_range` byte offsets:

```json
{ "kind": "NODE_ROOT", "text_range": [0, 230], "children": [
  { "kind": "NODE_ATTR_SET", "children": [
    { "kind": "TOKEN_CURLY_B_OPEN", "text": "{" },
    { "kind": "NODE_KEY_VALUE", "children": [
      { "kind": "NODE_KEY", "children": [ {"kind":"NODE_IDENT","children":[{"kind":"TOKEN_IDENT","text":"contract"}]}, … ] },
      { "kind": "TOKEN_ASSIGN", "text": "=" },
      { "kind": "NODE_STRING", "children": [ …, {"kind":"TOKEN_STRING_CONTENT","text":"ada"}, … ] },
      { "kind": "TOKEN_SEMICOLON", "text": ";" } ] } ] } ] }
```

- **Cheapest data-emitting option: closure 51.8 MB, +13 MB over the jq baseline.** A ~3.6 MB
  Rust binary linking only glibc + libgcc. 9 ms to parse a 12.5 KB file.
- **Parser coverage is good** — a torture file (dynamic attrs, interpolation, `''…''` with
  `''${}` escape, `~/path`, `<nixpkgs>`, `inherit (x) a b`, `or` defaults, `->`, `1.5e3`,
  `@`-patterns, unquoted URI literals, legacy `let { body = …; }`) parsed with zero error nodes.
- **It cannot evaluate.** It keeps the structural guarantee from
  [Finding B](#finding-b-the-pre-auth-dependency-changes-category).

Three caveats, all verified:

1. **Silent misparse on syntax errors.** `--parse --output-format json` exits **0**, writes
   nothing to stderr, and emits plausible-but-wrong JSON containing a `NODE_ERROR` node — on a
   file missing a `;` it silently fused two bindings into a `NODE_APPLY`. Plain `--parse` (rnix
   text format) on the *same* file exits **1** with errors on stderr. The JSON path **must** be
   guarded: `jq '[.. | objects | select(.kind|test("ERROR")) | .kind] | length == 0'`.
2. **No attrpath merging.** `contract.identity.name` and `contract.identity = { … }` stay
   separate siblings — the consumer must merge them, i.e. re-implement a piece of module
   semantics, which is the cost the map wants to delete.
3. **Upstream is ARCHIVED** — `nix-community/nixpkgs-fmt`, last push 2024-07-24, version 1.3.0
   from 2022. A frozen security surface: no upstream fixes, ever.

JSON is verbose: 12.5 KB source → 1.1 MB pretty, 134 KB via `jq -c`.

A combination worth noting for the spike: **`nix-instantiate --parse | nixpkgs-fmt --parse
--output-format json | jq`** — real Nix attrpath-merge semantics, then JSON. Verified working;
the duplicate `contract.identity` correctly collapses. It costs both dependencies.

### `nixf-tidy` — a machine-readable syntax gate

`pkgs.nixf` 2.9.1 (nixd's parser, split out) ships `bin/nixf-tidy` (90 KB) plus
`lib/libnixf.so`. Reads Nix on **stdin**, emits **JSON**, `--pretty-print` available. Closure
**49.1 MB**.

It emits **diagnostics, not an AST** — `[]` on a clean file, structured LSP-style ranges and
suggested fixes on a broken one (`"sname":"parse-expected"`, `"message":"insert ;"`). That makes
it a good machine-readable *validator* to pair with nixpkgs-fmt, closing caveat 1 above. The C++
`libnixf.so` does expose a real AST if you are willing to link against it.

### hnix — dead on arrival

`haskellPackages.hnix` 0.17.0 exists, is cached, and is not broken (it built, ~14 min of
downloads, no source compile). But:

```console
$ hnix --parse --json test.nix
hnix: user error (Rendering expression trees to JSON is not implemented)
$ hnix --parse --xml test.nix
hnix: user error (Rendering expression trees to XML is not yet implemented)
```

Matches its source (`main/Main.hs:159-160`) — `--json`/`--xml` apply only to `--eval` results.
Its non-eval outputs are pretty-printed Nix source, a Haskell `Show` dump (`hnix -v 4 --parse`),
or a binary CBOR cache file.

**Closure 4,620,409,920 bytes = 4.62 GB — 119× the jq baseline** — because it drags GHC 9.10.3
into the *runtime* closure. Its parser fidelity is actually the best of the alternatives (it
parses free variables, unquoted URIs and legacy `let { body = …; }`), but its pretty-printer
round-trip is lossy for indented strings. Repo is live-ish (last push 2026-03-17) but the last
release is 0.17.0 from 2023-11-20, which is what nixpkgs ships.

### nixel — unmaintained, and its parser diverges

Top-level `nixpkgs#nixel` 4.1.0; single 2.0 MB Rust binary, closure 50.3 MB, verified
non-evaluating, ~44 ms/parse. `USAGE: nixel <--lex|--parse|--ast|--cst> [path]` — **no `--json`
of any kind**; all modes are Rust `{:#?}` pretty-print, so a bespoke parser would be needed.

**Two parser divergences from CppNix 2.34**, each isolated and verified — unquoted URI literals
(`http://example.com/a`) and legacy `let { body = …; }` are both **rejected** by nixel and
**accepted** by CppNix, rnix and hnix. Last code push **2022-11-25**; nixpkgs ships 4.1.0 while
crates.io is at 5.2.0 — a major version behind an already-abandoned crate. A parser that
disagrees with CppNix about what is valid Nix is disqualifying for a security boundary that must
agree with the module system.

### Rejected outright

| Tool | Why |
| --- | --- |
| `nil` 2025-06-13 (85.9 MiB) | `nil parse` gives a clean rowan text tree but **no JSON**, and `--help` warns *"The output … are for human and should not be relied on."* `nil ssr` is a pure-syntax query engine but rejects `contract.identity.username = $v;` as "Multiple top-level expressions" |
| `nixd` 2.9.1 (730.8 MiB) | No non-LSP CLI at all |
| `nixfmt` 1.4.0 (77.8 MiB) | `-a/--ast` is ANSI-colour-escaped Haskell `Show`, **exits 1**, documented "only for debugging" |
| `alejandra` 4.0.0 (50.1 MiB) | **No AST flag** — options are `-c`, `-e`, `--experimental-config`, `-q`, `-t` only |
| `deadnix` 1.3.1 (49.9 MiB) | `-o json` is lint findings only |
| `nix-editor` | **Not in nixpkgs** — `nix search` returns `{}`; could not test its `--get` semantics |
| `nurl` 0.4.0 | Its `-p/--parse` parses **URLs** |
| `nix-melt` 0.1.3 | A `flake.lock` TUI; no Nix-language parser |

---

## Appendix: fixtures and prototype

Fixtures and the prototype reader live in the session scratchpad (`…/scratchpad/ast/`), not in
the repo:

| File | Probes |
| --- | --- |
| `identity.nix` | the happy path: dotted paths + a merged block |
| `hostile.nix` | escapes, `''…''`, `let`, `+`, `builtins.readFile`, `++`, a quoted key |
| `spoof.nix` | `"a${""}b"`, `if`, `rec`, `with`, `builtins.map`, `inherit`, a decoy key |
| `sortattack.nix` | a decoy key that sorts before the real one |
| `desync.nix` | a key ending in `\\` |
| `scalars.nix` | `true` `null` `1` `1.5` paths `<nixpkgs>` `""` `[ ]` `{ }` |
| `comments.nix` | comment stripping, `imports`, a sibling option namespace |
| `fnmod.nix` / `rectest.nix` | a `{ config, lib, ... }:` module; a `rec { }` module |
| `evil2.nix` | `fetchurl` + `import <nixpkgs>` + `trace` + `readFile /etc/shadow` + infinite recursion |
| `mod-main.nix` / `mod-extra.nix` / `eval-module.nix` | the `imports` disagreement |
| `ctrl.nix` / `nul.nix` / `badutf8.nix` / `unterm.nix` / `cr.nix` | byte-level hostility |
| `deep.nix` / `deepparen.nix` / `deepattr.nix` / `big.nix` | resource exhaustion |
| `read-canonical.pl` | the 104-line strict reader |
| `extract.jq` | the 5-line asserting Lix-AST extractor |
| `robust.sh` / `depth.sh` / `sweep.sh` / `t.sh` / `lix2.sh` / `evilcheck.sh` | the harnesses |

**These are worth recreating as a conformance fixture set in #78 whichever candidate wins** —
most are candidate-independent, and the `imports`, lambda-module, `rec`, interpolation and
concatenation cases are exactly the ones that decide whether the extractor can disagree with the
module system.

## What could not be verified

- The exact closure of Lix 2.94.2 as pinned in this repo's `flake.lock` (not in the local store;
  not built).
- `nix eval --parse` failing as an unrecognised flag — verified from CppNix source only; the
  sandbox blocked running `nix eval` directly.
- Any platform other than `x86_64-linux`.
- tree-sitter CLI/grammar ABI compatibility across *different* nixpkgs pins (both came from one
  pin here and matched).
- Whether rnix (via nixpkgs-fmt) has parser divergences beyond the torture corpus used — the
  testing was sampling, not a conformance suite.
- `nix-editor`'s get-semantics — not packaged.
