# Posture floor and unlock KDF parameters, measured

Measurements for [#114](https://github.com/palebluebytes/host-user-contract/issues/114), under map
[#104](https://github.com/palebluebytes/host-user-contract/issues/104). Companion to
[`2026-08-24-key-delivery-prior-art.md`](2026-08-24-key-delivery-prior-art.md) (#105), which
supplies the threat model and the parameter *candidates*; this document supplies the numbers.

**This document decides nothing.** It is the evidence behind #114's answer.

## The machine

Every figure below was measured on **one machine** on 2026-08-25:

| | |
| --- | --- |
| CPU | Intel Core i7-8650U (4 cores / 8 threads), **2.2 GHz all-core** under load, `powersave` governor |
| RAM | 15.8 GiB |
| OS | NixOS `x86_64-linux`, kernel 6.18.38, cgroup v2 |
| Load average during the runs | **17–22** — the box was busy throughout |
| Tools | `age` 1.3.1, `rage` 0.12.1, `perl` 5.42.0, `mkpasswd`/`libxcrypt` from the `flake.lock` nixpkgs pin, `python3` (OpenSSL `scrypt`) |

This is a 15 W 2017 mobile chip running at its all-core power limit on a loaded system — it is
already toward the **slow** end of any plausible fleet, which is the case #114 asked for. It is
still one machine. Nothing here was measured on ARM, on a Raspberry Pi, or on a seat with a
spinning disk.

Timings are reported as **min of N**. Under contention the minimum is the best available estimate
of the uncontended cost; the spread is reported so the contention is visible. It was small: at
yescrypt cost 9, min 635 ms vs median 648 ms vs max 905 ms over 15 runs.

## 1. yescrypt cost → prefix, time, memory

`mkpasswd -m yescrypt -R <n>`, reading the passphrase on stdin. Prefixes are **as predicted** by
#114's table, read from libxcrypt's `lib/crypt-yescrypt.c` (`N = 1ULL << (count + 7)`, `r = 32`,
memory `128 * r * N`):

| `-R` | prefix | N | nominal memory | `mkpasswd` net ms | peak RSS |
| --- | --- | --- | --- | --- | --- |
| 1 | `$y$j75$` | 1024 | 1 MiB (r=8) | 7.0 | 3.5 MiB |
| 3 | `$y$j7T$` | 1024 | 4 MiB | 17.5 | 6.5 MiB |
| **5** (libxcrypt default — what ADR-0004 gets today) | **`$y$j9T$`** | 4096 | 16 MiB | 46.3 | 18.5 MiB |
| 7 | `$y$jBT$` | 16384 | 64 MiB | 179.9 | 66.5 MiB |
| **9** (candidate) | **`$y$jDT$`** | 65536 | **256 MiB** | **674** | **258 MiB** |
| 11 | `$y$jFT$` | 262144 | 1 GiB | 2671 | 1027 MiB |

Process-startup baseline (4.0 ms, `mkpasswd --version` × 20) subtracted. Peak RSS via
`/usr/bin/time -f %M`, and it tracks `128 · r · N` to within ~1 %.

## 2. The path the greeter actually runs — `perl crypt`

`greeter/auth.nix` verifies with `perl -e 'print crypt($ARGV[0], $ARGV[1])'`. That is the code
whose latency a person waits on, so it — not `mkpasswd` — is the number that matters.

| `-R` | prefix | min ms | median ms | max ms | peak RSS | round-trip | wrong password |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 5 | `$y$j9T$` | **39.5** | 41.4 | 53.6 | 21.6 MiB | MATCH | rejected |
| 7 | `$y$jBT$` | **158.1** | 165.3 | 243.5 | 69.7 MiB | MATCH | rejected |
| 9 | `$y$jDT$` | **635.4** | 647.7 | 905.0 | 261.6 MiB | MATCH | rejected |
| 11 | `$y$jFT$` | **2616.7** | 2673.4 | 3044.7 | 1029 MiB | MATCH | rejected |

n = 15 (n = 7 at cost 11).

- **perl 5.42's `crypt` handles `$y$jDT$`.** It re-hashes and returns a byte-identical string, and
  rejects a wrong password at every cost. #114's item 4 is discharged: the greeter can verify the
  candidate floor.
- **Cost scales exactly as libxcrypt's formula says** — ~4× per `+2` of `-R`, i.e. ~2× per doubling
  of N. No surprises, no cliff.
- `perl crypt` is consistently *slightly faster* than `mkpasswd` at the same cost (635 vs 674 ms at
  cost 9); the difference is process setup, not the KDF.

## 3. The unlock side — age's scrypt

`age -p` emits `-> scrypt <16-byte salt> 18` — work factor **18** (N=2^18, r=8, p=1 = **256 MiB**),
confirmed by reading the header of a file produced here. `age --help` exposes **no** work-factor
flag, matching #105's reading of `cmd/age/age.go`.

**End-to-end `age -d`** (real binary, real file, passphrase fed through a pty; 33 ms
`script`+`age` startup subtracted, n = 7):

| | min | mean | max | peak RSS |
| --- | --- | --- | --- | --- |
| `age -d`, logN=18 | **2.17 s** | 2.38 s | 2.93 s | 263 MiB |

**The same KDF via OpenSSL** (`hashlib.scrypt`, identical parameters and the spec's
`"age-encryption.org/v1/scrypt" || salt` label), measured in the same session:

| logN | memory | min s |
| --- | --- | --- |
| 14 | 16 MiB | 0.095 |
| 16 | 64 MiB | 0.410 |
| 17 | 128 MiB | 0.811 |
| **18** | **256 MiB** | **1.64** |
| 19 | 512 MiB | 3.27 |

Two things follow, and both correct a number the map has been carrying.

- **Go's scrypt is ~1.3× slower than OpenSSL's** at identical parameters (2.17 s vs 1.64 s). An
  attacker uses the fast implementation; the user pays the slow one.
- **#105's "~1.03 s for age's default" is not what a person pays.** That figure was OpenSSL on an
  idle machine. Through the `age` CLI on this hardware the honest number is **~2.2 s**, which is
  also 2× age's own *"1s on a modern machine"* source comment. Nothing is wrong with either
  measurement; they measure different things. **The user-facing figure is 2.2 s.**

### rage picks a *weaker* factor on a slow machine — measured

#105 read this out of rage's source. It reproduces, and the magnitude is worse than the doc's
framing suggests:

| producer CPU budget | work factor rage chose | memory |
| --- | --- | --- |
| `CPUQuota=100%` | 18 | 256 MiB |
| `CPUQuota=25%` | **17** | 128 MiB |
| `CPUQuota=10%` | **14** | **16 MiB** |

A producer on a slow or busy machine silently ships a 16 MiB blob — *weaker than the cost-5 hash it
was meant to out-price* — and the header records the weakness in plain text with no warning. Go
`age` decrypted a rage-produced blob here without complaint (verified at factor 18; the spec and
`scrypt.go` place the accepted range at 1–22, so a factor-14 blob is inside it — **inferred, not
measured**). rage's only CLI knob is `--max-work-factor`, and it is decrypt-side.

## 4. Memory is the binding constraint, and it fails silently

Measured with `systemd-run --user --scope -p MemoryMax=<cap> -p MemorySwapMax=0` — a hard cap, no
swap. (Sanity-checked: a 200 MiB perl allocation under a 4 MiB cap is killed.)

| operation | nominal | OK at | **killed at** |
| --- | --- | --- | --- |
| `perl crypt`, yescrypt cost 7 | 64 MiB | 72 MiB | **64 MiB** |
| `perl crypt`, yescrypt cost 9 | 256 MiB | 272 MiB | **256 MiB** |
| `age -d`, scrypt logN=18 | 256 MiB | 272 MiB | **256 MiB** |

- **Nominal is not sufficient.** Both sides need **>256 MiB and ≤272 MiB** of *available* memory.
  Budget **272 MiB**, not 256.
- **The two 256 MiB figures land on the same real requirement** — the "equal oracles" symmetry
  holds exactly on the memory axis.
- **The failure mode is a silent OOM kill.** No error, no message, no exit code from the tool: the
  process is killed by the kernel. Anything that must "say so first" (#107) has to check memory
  *before* it starts, because there is no failure to catch afterwards.

### The pair is sequential, so the peak does not add

Verify-then-unwrap, back to back, inside a **320 MiB** cgroup with swap off:

```
verify: 0.702 s
unwrap: 2.286 s
TOTAL : 2.988 s
```

Identical to the uncapped run (0.724 / 2.301 / **3.025 s**). **Peak requirement is ~272 MiB, not
~544 MiB.**

## 5. Attacker cost, in the only metric that fits a memory-hard KDF

Time alone understates a memory-hard function: doubling memory halves how many guesses fit in an
attacker's RAM *and* costs time. The standard measure is **area × time** (memory × duration).
Using the fastest implementation measured for each — `perl crypt`/libxcrypt for the hash, OpenSSL
for scrypt — because the attacker picks the fast one:

| artifact | memory | time | area×time | vs the unwrap |
| --- | --- | --- | --- | --- |
| `hashedPassword`, cost 5 — **today** | 16 MiB | 0.040 s | **0.63 MiB·s** | **667× cheaper** |
| `hashedPassword`, cost 7 | 64 MiB | 0.158 s | 10.1 MiB·s | **42× cheaper** |
| `hashedPassword`, **cost 9** | 256 MiB | 0.635 s | **163 MiB·s** | **2.6× cheaper** |
| `hashedPassword`, cost 11 | 1024 MiB | 2.617 s | 2679 MiB·s | 6.4× *more expensive* |
| `key.password.age`, logN=18 | 256 MiB | 1.64 s | **420 MiB·s** | — |

This is the table #114 exists to produce. It says plainly what each candidate buys, and it does not
say "equal".

## 6. What the person pays, per login

Added to every login, on top of everything the greeter already does:

| floor | verify | unwrap | **total added** | peak memory |
| --- | --- | --- | --- | --- |
| cost 5 (today, no delivery) | 0.04 s | — | 0.04 s | 22 MiB |
| cost 7 + delivery | 0.16 s | 2.30 s | **2.46 s** | 272 MiB |
| **cost 9 + delivery** | **0.70 s** | **2.30 s** | **3.02 s** | **272 MiB** |
| cost 11 + delivery | 2.62 s | 2.30 s | 4.92 s | 1.03 GiB |

**The unwrap dominates.** Choosing 9 over 7 adds 0.54 s to a login that already grew by 2.3 s —
about a fifth of the added wait — and adds **nothing at all** on the memory axis, because the
unwrap already demands 272 MiB.

**On slower hardware, scale linearly.** Both KDFs are linear in N and in clock speed. A seat 2×
slower than this one pays ~6 s; 4× slower, ~12 s. Not measured.

## 7. The asymmetry that costs cost 9 something real

The unwrap is paid only where a key is delivered. **The posture floor is paid everywhere.**

`greeter/auth.nix` verifies the published `hashedPassword` at every login on every seat, including
a seat that (per #107) launches a **secret-free** session because it cannot help. So opting into
key delivery raises the cost of *every* login the user ever performs, on seats that will never
unwrap anything:

- **cost 9**: +0.63 s and a **272 MiB** floor, everywhere.
- **cost 7**: +0.16 s and a 72 MiB floor, everywhere.

The consequence is not "degrades gracefully" but **lockout**: a seat with less than ~272 MiB
available at greeter time cannot verify the password at all, so the user cannot log in — the
secret-free fallback never gets a chance to run. In practice any seat running a graphical desktop
has this memory to spare, but the sentence belongs in the ADR unhedged rather than discovered later.

## 8. A naming collision, noticed in passing

**`posture` is already taken in this codebase.** It means the *restricted-eval* posture of
ADR-0019 — `greeter/bind.nix`, `greeter/mode-select-eval.nix` and `greeter/account-plan-eval.nix`
all use it that way, tier-dispatched. There is no `mkIdentityPostureCheck` seam in the tree;
#105 named one as a hypothetical and it does not exist.

Whatever the ADR calls the credential-strength floor, *"posture"* on its own will read as the eval
posture to anyone working in `greeter/`.

## Reproducing

The scripts are in [`kdf-parameters/`](kdf-parameters/). One caveat that cost a full round of bad
numbers here: **`systemd-run` expands `$` in its command arguments**, so passing a `$y$…` hash as
an argv element silently corrupts it and the verification "passes" against garbage. Pass hashes on
stdin.
