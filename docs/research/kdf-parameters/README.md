# Measurement scripts for #114

Exactly the scripts that produced [`../2026-08-25-kdf-parameters-measured.md`](../2026-08-25-kdf-parameters-measured.md),
copied verbatim from the session that ran them. They are **throwaway benchmark harnesses**, not
project code: they take no arguments, hardcode a passphrase, and write scratch files into the
working directory.

Run them from a scratch directory, in this order — later scripts consume artifacts the earlier
ones leave behind:

| script | measures | leaves behind |
| --- | --- | --- |
| `bench-yescrypt.sh` | `mkpasswd -m yescrypt -R {1,3,5,7,9,11}` — emitted prefix, wall clock, peak RSS | — |
| `bench-perl.sh` | `perl crypt` round-trip and cost at each `-R` — the greeter's real path | — |
| `bench-min.sh` | min/median/max for `perl crypt` and `age -d`, plus `k.age` | `plain.txt`, `k.age` |
| `bench-scrypt.py` | OpenSSL `scrypt` at age's parameters, logN 14–19 | — |
| `verify.pl` | reads `password\nhash\n` on **stdin** — used inside cgroups (see caveat) | — |
| `memcaps.sh` | `MemoryMax` thresholds and the OOM failure mode | — |
| `seq.sh` | verify-then-unwrap end to end; needs `in.txt`, `pw.txt`, `k.age` | — |
| `slowrage.sh` | the work factor `rage` picks under `CPUQuota`; needs `plain.txt` | `rq.age` |

Tools come from `nix shell nixpkgs#{age,rage,python3,util-linux,bc,time}`; `mkpasswd` and `perl`
are expected on `PATH`.

**The caveat that cost a round of bad numbers.** `systemd-run` performs `$`-expansion on its
command arguments, so a `$y$jDT$…` hash passed as an argv element arrives mangled — and
`crypt($pw, "")` then compares equal to the mangled value, so the check reports a **false pass**.
That is why `verify.pl` exists and reads its inputs on stdin. Any future measurement that puts a
crypt hash near `systemd-run` must do the same.
