# How other systems hand a user their key at a machine that has never met them

Research for [#105](https://github.com/palebluebytes/host-user-contract/issues/105), under map
[#104](https://github.com/palebluebytes/host-user-contract/issues/104).

**Question.** At a stranger seat the only inputs are the user's **public repo** and **what the
person types**. Plenty of shipped systems solve some version of this. What do they actually do, and
what does each pay for it?

**This document decides nothing.** The decision is the ADR [#104](https://github.com/palebluebytes/host-user-contract/issues/104)
is walking towards; the immediate consumer is [#108](https://github.com/palebluebytes/host-user-contract/issues/108)
(*one secret in the head, or two?*), which this blocks.

Every claim carries a URL to the artifact that owns it — spec text, man page, source, or vendor
whitepaper. Claims marked **measured here** were run on this machine on 2026-08-24: NixOS
`x86_64-linux`, 8 cores, `age` 1.3.1, `libxcrypt` 4.5.2, `mkpasswd` and `python3` from the same
nixpkgs pin as `flake.lock`. Anything neither cited nor measured is marked *unverified*.

---

## Summary

Same six questions, every system.

| System | Human holds | Wrapped key lives | Offline? | What a public-artifact attacker grinds | Recovery | Password change |
| --- | --- | --- | --- | --- | --- | --- |
| **systemd-homed** (LUKS2) | password / FIDO2 / PKCS#11 / recovery key | LUKS2 header **and** `~/.identity`, both travelling with the home | **yes** | argon2id, 64 MiB — *but* the signed record also ships a `crypt(3)` hash at libxcrypt defaults | extra keyslot: 256-bit modhex recovery key. No escrow | **survives** — volume key is immutable; keyslots rewrap. Two-pass add-then-destroy |
| **homed** (fscrypt backend) | same | `trusted.fscrypt_slot<N>` xattrs | yes | **PBKDF2-HMAC-SHA512, 600 000** — not memory-hard | same | survives, but destructive in-place, no rollback |
| **google/fscrypt** | login passphrase / custom passphrase / raw key | `<mount>/.fscrypt/protectors/…` (custom), `/.fscrypt` (login) | **yes** | Argon2id at whatever the enrolling machine benchmarked; HMAC verifier in the protector file | second protector on the same policy; auto-generated 94-bit recovery passphrase | **survives** — policy key immutable, protector rewraps |
| **Mozilla Accounts / Sync** | password (+ optional 160-bit recovery key) | Mozilla's DB (`wrapWrapKb`) and CloudKit | **no** — `kB` is server-generated randomness | **PBKDF2-HMAC-SHA256, 1000 iterations** on an active compromise | 160-bit account recovery key wrapping `{kA,kB}`; else **data destroyed** | **change survives, reset does not** |
| **iCloud Keychain escrow** | 4–6 digit passcode / iCloud Security Code | Apple's HSM cluster, double-wrapped to passcode **and** cluster pubkey | **no** | nothing — the blob never leaves the HSM | recovery contacts (SPAKE2+), 28-char recovery key | n/a — escrow is re-enrolled |
| **1Password** | password **+ 128-bit Secret Key (carried, not memorised)** | 1Password servers + local cache | only on an **already-enrolled** device | **nothing gridable** — no verification oracle without the Secret Key | Recovery Group / recovery key. Vendor cannot help | **survives** — AUK rewraps the keyset. See A.5 caveat |
| **Bitwarden** | password only | Bitwarden servers | read-only, on an already-unlocked client | PBKDF2 600 000, or Argon2id 32 MiB/t=6/p=4 | Emergency Access / org recovery. Else none | **survives**; separate opt-in *account key rotation* re-encrypts everything |
| **age / rage scrypt** | passphrase | wherever you put the file | **yes** | scrypt N=2^18, r=8, p=1 = **256 MiB**, ~1.03 s (**measured here**) | **none** — and the format forbids the shape recovery needs | **no** — changing the passphrase rewrites the whole file |

---

## Headline: seven findings that bear on the map's premises

### 1. Every shipped system that makes a *weak* secret safe does it with a party that is not the user

This is the survey's central negative result, and it is unanimous.

- **Apple** makes a 4–6 digit passcode safe with an HSM cluster that counts to ten and then burns
  the record: *"After the 10th failed attempt, the HSM cluster destroys the escrow record and the
  keychain is lost forever."*
  ([Escrow security for iCloud Keychain](https://support.apple.com/guide/security/escrow-security-for-icloud-keychain-sec3e341e75d/web))
- **Mozilla** makes a human password safe for `kB` by injecting 32 bytes the server generated:
  *"Data that is encrypted using key material derived from `kB` cannot be used to mount a
  brute-force guessing attack on the user's password, because it incorporates a full 32 bytes of
  entropy via `wrapKb`."*
  ([Scoped Keys](https://github.com/mozilla/ecosystem-platform/blob/master/docs/explanation/scoped-keys.md))
- **1Password** makes it safe with 128 bits the human *carries but does not memorise*: *"An
  attacker who captures server data would need to make guesses at a user's account password **and**
  have the user's 128-bit strong Secret Key."*
  ([whitepaper](https://1passwordstatic.com/files/security/1password-white-paper.pdf), §4)

The map's settled premise is **offline baseline; network is optional strengthening**. That premise
does not merely make Apple's and Mozilla's answers inconvenient — it removes the entire *class* of
"make the weak secret safe" solutions. What is left is 1Password's answer (add carried entropy) or
no answer at all (budget bits and accept the grind).

**Corollary, stated bluntly.** With a public repo, no network, and an unenrolled seat, *the entropy
of what the human types is the whole security margin*. A memory-hard KDF is a constant-factor
lever — worth perhaps 20 bits against a funded attacker — not the 3–4 orders of magnitude a
hardware counter buys. Any rate limit stored next to the ciphertext is advisory: the attacker
snapshots it before the first guess.

### 2. The universal hierarchy: the password is never the key, it only wraps one

Every single system here separates an **immutable random data key** from **N mutable credentials
that each wrap a copy of it**. It is the same shape five times over:

| System | Immutable data key | Mutable wrapper |
| --- | --- | --- |
| LUKS2 / homed | volume key | keyslots |
| google/fscrypt | policy key (= kernel master key) | protectors |
| Mozilla | `kB` (server-generated randomness) | `unwrapBKey` (XOR mask from the password) |
| 1Password | personal keyset / private key | AUK = PBKDF2(pw) ⊕ HKDF(Secret Key) |
| Bitwarden | User Symmetric Key | Stretched Master Key |

This is what makes password change O(1) instead of O(size-of-home), and it is what makes
"recovery" expressible at all. It is the one design element that is **free, local, and needs no
server** — so it is available to this design in full.

### 3. Recovery is always "one more wrapping of the same key", never escrow

No system in this survey recovers a forgotten secret cryptographically. Every one of them
pre-arranges a **second, independent, high-entropy path to the same key**:

| System | Recovery artifact | Entropy |
| --- | --- | --- |
| systemd-homed | `modhex64` recovery key, an extra LUKS2 keyslot | **256 bits** ([`recovery-key.h`](https://github.com/systemd/systemd/blob/main/src/shared/recovery-key.h)) |
| google/fscrypt | auto-generated recovery passphrase, an extra protector | **~94 bits** — *"20 random characters in a-z is 94 bits of entropy"* ([`actions/recovery.go`](https://github.com/google/fscrypt/blob/master/actions/recovery.go)) |
| Mozilla | account recovery key wrapping a JWE of `{kA,kB}` | **160 bits** ([`recoveryKey.ts`](https://github.com/mozilla/fxa/blob/main/packages/fxa-auth-client/lib/recoveryKey.ts)) |
| Apple | recovery key | 28 characters ([HT109345](https://support.apple.com/en-us/109345)) |
| 1Password | recovery key (HKDF → identifier / auth / encryption subkeys) | CSPRNG, client-side ([whitepaper](https://1passwordstatic.com/files/security/1password-white-paper.pdf) §12.6) |

The map's constraint — *the design must not make "I forgot" unrecoverable by construction* — is
therefore satisfiable **offline**, and this is the mechanism. It is also the one place the
public-repo constraint stops being a liability: 160 bits is not brute-forceable, so a
recovery-key-wrapped blob is safe to publish.

Two warnings the vendors put in writing, both about the *ergonomics* rather than the crypto:

- **Recovering must not silently remove the ability to recover again.** Mozilla: *"Click Forgot
  password? Note: This will also reset your account recovery key."* Apple: *"When you set up a
  recovery key, you turn off Apple's standard account recovery process."*
  ([HT109345](https://support.apple.com/en-us/109345))
- **Do not store the recovery secret inside the thing it recovers.** Apple says it explicitly:
  *"Don't store your recovery key in your Apple Passwords app, iCloud Photos, Notes, or iCloud
  Drive."* fscrypt commits the same sin by default and admits it — the generated passphrase starts
  life *"in a file in the encrypted directory itself"*, with instructions telling the user to move
  it ([README](https://github.com/google/fscrypt/blob/master/README.md)).

### 4. age's scrypt stanza structurally forbids the shape recovery needs

The age v1 spec ([C2SP `age.md`](https://github.com/C2SP/C2SP/blob/main/age.md)):

> An scrypt stanza, if present, **MUST be the only stanza in the header**. In other words, scrypt
> stanzas MAY NOT be mixed with other scrypt stanzas or stanzas of other types. This is to uphold
> an expectation of authentication that is implicit in password-based encryption. The identity
> implementation MUST reject headers where an scrypt stanza is present alongside any other stanza.

**Verified here** on age 1.3.1:

```
$ echo hi | age -r age1yd5j…vsvmqa5d2gj -p
age: error: -p/--passphrase can't be combined with -r/--recipient
```

The library enforces it independently of the CLI — `an scrypt recipient must be the only one`
([`scrypt.go`](https://github.com/FiloSottile/age/blob/main/scrypt.go)) — and rage has a dedicated
`EncryptError::MixedRecipientAndPassphrase` plus a spec test vector `scrypt_and_x25519`.

So the finding-3 pattern (*wrap the same key under a second recipient*) **cannot be applied at the
payload-file level whenever a passphrase is involved.** Upstream's own answer is to move the
indirection one layer up, and it is documented in
[`age-plugin-batchpass(1)`](https://github.com/FiloSottile/age/blob/main/doc/age-plugin-batchpass.1.ronn):

```
$ age-keygen -pq | age -p -o encrypted-identity.txt
$ age -r age1pq1cd[...] file.txt > file.txt.age
$ age -d -i encrypted-identity.txt file.txt.age > file.txt
```

**That is finding 2 achieved with stock tooling**: the passphrase wraps a *key*, not the *data*.
Changing the passphrase rewrites one small identity file and leaves every payload untouched. It
also means "two independent unwrapping paths" is expressible as *two encrypted identity files
carrying the same identity* — one scrypt-wrapped under the remembered password, one scrypt-wrapped
under a printed recovery key — rather than one file with two recipients.

age itself is explicit that a passphrase is the weak option:

> Humans are notoriously bad at remembering and generating strong passphrases. age uses scrypt to
> partially mitigate this, which is necessarily very slow. **If a computer will be doing the
> remembering anyway, you can and should use native keys instead.**

### 5. 1Password's rotation caveat is *fatal* in a public git repo

Appendix A.5 of the [whitepaper](https://1passwordstatic.com/files/security/1password-white-paper.pdf),
verbatim:

> **A.5 Account password changes don't change keysets.** A change of account password or Secret Key
> does not create a new personal keyset, it only changes the Account Unlock Key (AUK) with which the
> personal key set is encrypted. Thus an attacker who gains access to a victim's old personal key
> set can decrypt it with an old account password and old Secret Key, and use that to decrypt data
> that was created by the victim **after** the change of the account password.

1Password can partly live with this because obtaining an old keyset requires a breach. **Git makes
the precondition free and permanent.** An old wrapped blob committed once is public forever, in
history, undeletable in practice. Therefore:

> In this design, a password change alone buys **zero** forward security. Only re-keying — a new
> root key and a re-encrypt of everything under it — means anything.

Bitwarden ships exactly that distinction as two separate product operations, and marks the
expensive one dangerous: *"Changing the KDF algorithm re-encrypts the protected symmetric key and
updates the authentication hash, much like a normal master password change. The symmetric
encryption key is not rotated, however, so vault data is not re-encrypted"* versus *"A key rotation
involves generating a new, random encryption key for the account and re-encrypting all vault
data"*, which *"is not a default option when changing a master password"*
([Bitwarden security whitepaper](https://bitwarden.com/help/bitwarden-security-white-paper/),
[KDF algorithms](https://bitwarden.com/help/kdf-algorithms/)).

### 6. The public `hashedPassword` is the *weaker* grind — with a number on it

This is [#108](https://github.com/palebluebytes/host-user-contract/issues/108)'s correlation
problem, quantified. [ADR-0004](../adr/0004-user-is-self-contained.md) mandates yescrypt (`$y$`) for
a public repo. What does that actually cost an attacker?

**Measured here.** `mkpasswd -m yescrypt` emits `$y$j9T$…`, and it does so at libxcrypt's cost
default. From [`lib/crypt-yescrypt.c`](https://github.com/besser82/libxcrypt/blob/develop/lib/crypt-yescrypt.c):

```c
  /* Valid cost parameters are from 1 to 11.  The default is 5. */
  if (count == 0)
    count = 5;
  …
      params.r = 32;                  // N in 4KiB
      params.N = 1ULL << (count + 7); // 3 -> 1024, 4 -> 2048, ... 11 -> 262144
```

Cost 5 → `N = 4096`, `r = 32`, `p = 1`. The same file states the memory formula: *"128 bytes * r *
N = total amount of memory used for hashing"* → **16 MiB**. The encoding is visible in the hash
prefix, and tracks the cost monotonically (**measured here**):

| `mkpasswd -R` | prefix | N | memory |
| --- | --- | --- | --- |
| 1 | `$y$j75$` | 1024 | 1 MiB (r=8) |
| 3 | `$y$j7T$` | 1024 | 4 MiB (r=32) |
| **5 (default)** | **`$y$j9T$`** | **4096** | **16 MiB** |
| 7 | `$y$jBT$` | 16384 | 64 MiB |
| 11 | `$y$jFT$` | 262144 | 1 GiB |

Timing, **measured here** (20 iterations, process-startup baseline of 1.9 ms subtracted):
**~36 ms per hash at the default**, i.e. ~28 guesses/s/core, ~220/s on this 8-core box.

Set that against the guidance:

- **OWASP** floor for Argon2id is **19 MiB, t=2, p=1**, with 46 MiB/t=1/p=1 as the top of its
  equal-defence table
  ([Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)).
- **RFC 9106**'s FIRST RECOMMENDED is **t=1, p=4, m=2^21 (2 GiB)**; SECOND RECOMMENDED is **t=3,
  p=4, m=2^16 (64 MiB)** ([RFC 9106 §4](https://www.rfc-editor.org/rfc/rfc9106.html#section-4)).

So the artifact ADR-0004 publishes sits at **16 MiB — below OWASP's Argon2id floor and 1/128th of
RFC 9106's headline recommendation.** The conclusion for #108 does not depend on how strong the
*unlock* KDF is:

> If one password does both jobs, an attacker grinds whichever artifact is cheaper. Today that is
> the published 16 MiB hash, not the unlock blob. Making the unlock KDF expensive does not help;
> the public hash is a parallel, cheaper oracle for the same secret, and ADR-0004's sentence *"the
> hash verifies a password and decrypts nothing"* stops being true the moment the two are the same
> password.

Two honest caveats. `$y$` cost is a **producer choice**, not a contract constant — a repo can ship
`-R 11` (1 GiB) and `mkIdentityPostureCheck` is the seam that could require it. And ADR-0004 is
right that yescrypt is memory-hard: 16 MiB genuinely blunts GPU parallelism in a way `$6$` does
not. The finding is not "yescrypt is broken", it is "the *cheaper of two* oracles sets the price,
and a design that couples them must price the cheaper one deliberately".

### 7. Nobody in this survey publishes the wrapped key on purpose

Every system here assumes the wrapped artifact is at least *nominally* protected:

- **homed** forces password verifiers into any distributed record. The signature covers the
  `privileged` section, which is exactly where `hashedPassword`, `recoveryKey[].hashedPassword` and
  the token hashes live ([USER_RECORD.md](https://github.com/systemd/systemd/blob/main/docs/USER_RECORD.md)),
  and those hashes come from `crypt_gensalt_ra(crypt_preferred_method(), 0, NULL, 0)` — libxcrypt
  *defaults* ([`libcrypt-util.c`](https://github.com/systemd/systemd/blob/main/src/shared/libcrypt-util.c)).
  Only `-EE`/`--export-format=minimal` strips them, and that removes the signature too.
- **fscrypt**'s protector file carries an HMAC that `Unwrap` checks *before* decrypting
  ([`crypto/crypto.go`](https://github.com/google/fscrypt/blob/master/crypto/crypto.go)) — a clean
  verification oracle at exactly the stored Argon2id cost. Files are `0600`.
- **Mozilla, 1Password, Bitwarden** all sit behind authentication.

**This design would be the first to publish it deliberately.** No prior art de-risks the parameter
choice, and a public repo is strictly worse than a breached server: the attacker has it by default,
forever, with no detection and no revocation.

---

## The systems, one at a time

### systemd-homed

**1. What the human holds.** Four credential kinds, all funnelling to a string password at the
layer below — *"used as string password for the further layers of the stack"*
([USER_RECORD.md](https://github.com/systemd/systemd/blob/main/docs/USER_RECORD.md)):
`hashedPassword`, `pkcs11EncryptedKey`, `fido2HmacSalt` (a random salt HMAC'd by the token's
internal key), and `recoveryKey`.

**2. Where it lives.** Two copies of the record travel *with* the home
([HOME_DIRECTORY.md](https://github.com/systemd/systemd/blob/main/docs/HOME_DIRECTORY.md)):
`~/.identity` inside the home, and a LUKS2 token of type `systemd-homed` holding the record
*encrypted under the volume key* with its own IV. The rationale is stated: *"Linux kernel file
system implementations are generally not robust towards maliciously formatted file systems … Thus
it is necessary to validate the home directory image **before** mounting it."*

**3. Offline.** Yes for `luks`, `directory`, `subvolume`, `fscrypt`. No for `cifs` (*"the user
record needs to be registered locally before it can be mounted for the first time"*).

**4. Offline-attack surface.** LUKS2's JSON header is plaintext, including per-keyslot `kdf` type,
`time`, `memory`, `cpus` and `salt`
([LUKS2 on-disk format](https://gitlab.com/cryptsetup/cryptsetup/-/raw/main/docs/on-disk-format-luks2.pdf)).
homed's defaults, from [`src/shared/user-record.c`](https://github.com/systemd/systemd/blob/main/src/shared/user-record.c)
(the man page documents the *options* but states no defaults):

| Field | Default | Source comment |
| --- | --- | --- |
| `luksPbkdfType` | `argon2id` | |
| `luksPbkdfHashAlgorithm` | `sha512` | |
| `luksPbkdfTimeCostUSec` | **500 ms**, as a *benchmark target* | *"in contrast to libcryptsetup's 2s, which is just awfully slow on every login"* |
| `luksPbkdfMemoryCost` | **64 MiB** | *"since this should work on smaller systems too"* |
| `luksPbkdfParallelThreads` | **1** | *"since this should work on smaller systems too"* |
| `luksVolumeKeySize` | 32 bytes | |

Token-derived secrets get a deliberately *cheap* KDF, because they are already high-entropy —
`build_minimal_pbkdf()` uses PBKDF2 with `.iterations = 1000, /* recommended minimum count for
pbkdf2 according to NIST SP 800-132 */`
([`homework-luks.c`](https://github.com/systemd/systemd/blob/main/src/home/homework-luks.c)). The
recovery key is *not* in that class and goes through argon2id.

Identity is not confidential: the username is the file name (`/home/<user>.home`), the GPT
partition label, the LUKS2 label, and the inner filesystem label.

**The roaming gate.** This is the decisive fact:

> User records are cryptographically signed … **For a user to be permitted to log in locally the
> public key matching the signature of their user record must be installed.**
> — [systemd-homed.service(8)](https://github.com/systemd/systemd/blob/main/man/systemd-homed.service.xml)

`manager_verify_user_record()` tries the local private key, then every registered `*.public`, and
returns `-ENOKEY` otherwise; `homed-home.c` then refuses fixation with *"User record %s is not
signed by any known key, refusing."* Unsigned records are refused too. **systemd-homed's answer to
"a machine that has never met the user" is: install one artifact first.** The only escape,
`--seize`/`-EE`, needs root at the destination and destroys the provenance the signature existed
for.

**5. Recovery.** *"A recovery key is a computer generated access key that may be used to regain
access to an account if the password has been forgotten"*
([homectl(1)](https://github.com/systemd/systemd/blob/main/man/homectl.xml)). 256 bits of CSPRNG in
modhex (alphabet `cbdefghijklnrtuv`), 64 characters in dash-separated groups of 8. *"An account may
have any number of recovery keys defined."* **No escrow anywhere.**

**6. Password change.** The reference implementation, and worth copying verbatim. From
[`homework-luks.c`](https://github.com/systemd/systemd/blob/main/src/home/homework-luks.c):

> Rotate the LUKS key slots in two passes, so that at every on-disk state at least one valid key
> slot exists for each password the user currently holds. First add all new passwords into free key
> slots (purely additive, hence non-destructive), and only once that fully succeeded destroy the
> old slots. If an add fails (e.g. the argon2 PBKDF, which is intentionally memory hungry, hits
> OOM), we roll back the slots added so far and return with the pre-existing slots untouched. The
> reverse order … would, on such a failure, leave the slot destroyed with no replacement,
> permanently locking the user out.

It also pre-flights capacity and returns `ENOSPC` rather than starting a rotation it cannot finish.
Because the embedded record is encrypted under the *volume key*, a password change does not re-key
it either.

**homed's fscrypt backend is a different and worse story.** Keyslots live in `trusted.fscrypt_slot<N>`
xattrs — *"extended attributes are not encrypted by fscrypt and hence are suitable for carrying the
key slots"* — with `#define FSCRYPT_SLOT_PBKDF2_ITERATIONS UINT32_C(600000)` and a legacy v1 format
that is *"AES-256-CTR, all-zero IV"* with `0xFFFF` iterations and no authentication tag, only
upgraded on the next password change
([`homework-fscrypt.c`](https://github.com/systemd/systemd/blob/main/src/home/homework-fscrypt.c)).
Rotation there overwrites slots in place with no rollback.

**7. Mistakes to avoid copying.**

- **Do not publish a signed record that embeds password verifiers.** The signature covering
  `privileged` *forces* `crypt(3)` hashes into every distributed copy. Split the artifact:
  signature over public material, verifiers never outside the encrypted blob.
- **Do not adopt "install the signer's key first"** — that is precisely the per-user prior state
  the map forbids.
- **Do not benchmark KDF cost at enrolment.** A 500 ms target writes very different iteration
  counts on a Pi and on a workstation, and the attacker gets the weakest. Pin the parameters. The
  64 MiB *memory* floor is the part worth keeping.
- **Do copy** the recovery-key shape and the two-pass rotation.

### google/fscrypt and pam_fscrypt

**1. What the human holds.** Exactly three protector types — `pam_passphrase`, `custom_passphrase`,
`raw_key` ([`metadata/metadata.proto`](https://github.com/google/fscrypt/blob/master/metadata/metadata.proto)).
**No hardware token support at all.**

**2–3. Where it lives, and offline.** Fully offline — the module's only runtime library is
`libpam.so`, and there is no network code anywhere in the tree. The hierarchy:

```
passphrase --Argon2id(salt, costs)--> wrapping key --Wrap--> protector key --Wrap--> policy key
                                                                                        |
                                                                    HKDF-SHA512 (in kernel)
                                                                                        v
                                                                                per-file keys
```

`Wrap` is AES-256-CTR + HMAC-SHA256 encrypt-then-MAC, subkeys via unsalted HKDF-SHA256
([`crypto/crypto.go`](https://github.com/google/fscrypt/blob/master/crypto/crypto.go)). The kernel
disclaims the top: *"The kernel does not do any key stretching; therefore, if userspace derives the
key from a low-entropy secret such as a passphrase, it is critical that a KDF designed for this
purpose be used"* ([kernel.org fscrypt](https://docs.kernel.org/filesystems/fscrypt.html)).

**Does it work at a machine with no per-user state? It depends on protector type, and the README
says so directly:**

> `pam_passphrase` (login passphrase) protectors are a bit different as they are always stored on
> the root filesystem, in `/.fscrypt`. This ties them to the specific system … Therefore, encrypted
> directories on a non-root filesystem **can't be unlocked via a login protector if the operating
> system is reinstalled or if the disk is connected to another system** — even if the new system
> uses the same login passphrase for the user.
> — [README](https://github.com/google/fscrypt/blob/master/README.md)

A `custom_passphrase` protector, by contrast, is a self-contained file next to the data in
`<mount>/.fscrypt/protectors/`, and it travels.

**4. Offline-attack surface, and the portability lesson.** The protector file exposes source type,
name, UID, salt, **the Argon2id costs**, and `{IV, encrypted_key, hmac}`. That HMAC is a
verification oracle at exactly the stored cost.

`fscrypt setup` benchmarks the machine to a **1 second** target, capped at **128 MiB** — *"large
enough to make the password hash very difficult to brute force on specialized hardware, but small
enough to work on most GNU/Linux systems"*
([`actions/config.go`](https://github.com/google/fscrypt/blob/master/actions/config.go)). But
crucially, **the costs are copied into the protector and travel with it**:
`protector.data.Costs = ctx.Config.HashCosts` at creation, and unlock reads
`crypto.PassphraseHash(passphrase, info.data.Salt, info.data.Costs)` — never the local config
([`actions/protector.go`](https://github.com/google/fscrypt/blob/master/actions/protector.go),
[`actions/callback.go`](https://github.com/google/fscrypt/blob/master/actions/callback.go)).

> **This is the most transferable mechanism in the survey.** The KDF parameters and salt are *data
> that travels with the wrapped key*, not configuration that lives on the machine. That is the
> property that makes a wrapped key openable at a seat that has never met the user. LUKS2's header
> does the same thing structurally; fscrypt makes it an explicit, portable, self-describing file —
> a form that could live in a git repo.

**5. Recovery.** Automatic, and triggered by exactly the condition this design cares about:

> `fscrypt encrypt` will automatically generate a recovery passphrase when creating a login
> passphrase-protected directory on a non-root filesystem. The recovery passphrase is simply a
> `custom_passphrase` protector with a randomly generated high-entropy passphrase.

**6. Password change.** Protector-layer only. `Rewrap` re-derives from the new passphrase using
**the same salt and same costs** and rewrites one protector file; nothing touches `PolicyData` or
the kernel keyring. The README states the intent: *"This allows a user to change how a directory is
protected without needing to reencrypt the directory's contents."* The known desync: root changing
a password without the old one cannot rewrap, and the module prints instructions to fix it
manually.

**7. Mistakes to avoid copying.**

- **Do not tie the protector's storage location to the machine.** This is fscrypt's own
  acknowledged flaw and the exact constraint here. Take the fix (always also create a travelling
  protector), not the flaw.
- **Do not let the strong KDF be gated by a weak one.** README: *"the security of login protectors
  is also limited by the strength of your system's passphrase hashing in `/etc/shadow`"* — the same
  coupling as finding 6.
- **Do not calibrate cost per-machine as policy.** The mechanism is right; the *value* still comes
  from whichever machine ran `fscrypt setup`, so a fleet ends up with no uniform parameter set.
- **Choose memory cost against the hardware floor, not the enrolling machine.** A 128 MiB protector
  needs 128 MiB on the weakest seat that must open it.
- *"Encryption is not access control"* — unlock is per-directory, not per-user.

### Mozilla Accounts / Firefox Sync

**1. What the human holds.** Email + password, optionally a **160-bit** account recovery key
(20 random bytes, Crockford base32, first character forced to `A` as a version marker).

**2. Where it lives.** `accounts.wrapWrapKb` / `authSalt` / `verifyHash` in Mozilla's DB; sync
records in Sync storage; the recovery bundle as a compact JWE (`A256GCM`, `alg: dir`) whose
plaintext is `JSON.stringify({kA, kB})`
([database-structure.md](https://github.com/mozilla/ecosystem-platform/blob/master/docs/reference/database-structure.md),
[`recoveryKey.ts`](https://github.com/mozilla/fxa/blob/main/packages/fxa-auth-client/lib/recoveryKey.ts)).

**3. Offline: no, structurally.** `kB` is *not derivable from the password at all* — *"the server
creates both kA and wrap(wrap(kB)) as randomly-generated 256-bit (32-byte) strings"*
([onepw protocol](https://mozilla.github.io/ecosystem-platform/explanation/onepw-protocol)). The
password yields only an XOR mask. Fetching `kB` needs a `keyFetchToken`, a live round trip, and a
verified email address.

**4. Offline-attack surface.**

```
salt             = "identity.mozilla.com/picl/v1/quickStretch:" + <email at signup>
quickStretchedPW = PBKDF2-HMAC-SHA256(password, salt, iterations = 1000, dkLen = 32)
authPW           = HKDF-SHA256(quickStretchedPW, "", ".../authPW",     32)
unwrapBKey       = HKDF-SHA256(quickStretchedPW, "", ".../unwrapBkey", 32)
kB               = wrapKB XOR unwrapBKey
```

([`crypto.ts`](https://github.com/mozilla/fxa/blob/main/packages/fxa-auth-client/lib/crypto.ts),
[`salt.ts`](https://github.com/mozilla/fxa/blob/main/packages/fxa-auth-client/lib/salt.ts)).
Server-side, `authPW` is stretched again with **scrypt (64k/8/1)**. Mozilla's own security analysis
is admirably blunt:

> a **"passive" attacker** … must do 64k/8/1-scrypt for each password guess. an **"active"
> attacker** … gets to perform an **"easy"** brute-force attack against the password (and thus kB),
> where "easy" means they must do **1000 rounds of PBKDF** for each guessed password.

and lists it as a known regression: *"**Weak client-side stretching** … This is relatively cheap."*
1000 iterations is ~1/600th of current OWASP PBKDF2 guidance, chosen for *"CPU+memory limitations
of slow mobile clients"*. A v2 exists in code (650 000 iterations, random 16-byte salt, versioned
salt label) but the in-repo rollout rule carries `DEFAULT_ROLLOUT_RATE = 0.0`
([key-stretch.js](https://github.com/mozilla/fxa/blob/main/packages/fxa-content-server/app/scripts/lib/experiments/grouping-rules/key-stretch.js));
production state is *unverified*.

**5–6. Reset vs change — the load-bearing distinction.**

| | **CHANGE** (knows the old password) | **RESET** (forgot it) |
| --- | --- | --- |
| `kB` | **preserved** | **regenerated at random** |
| How | fetch `wrap(kB)`, unwrap with old `unwrapBKey`, re-wrap with new, upload | server writes a fresh random `wrap(wrap(kB))` |
| Data | survives | *"All class-B data will be lost."* |

> Note that, since the forgotten-password client never learns kB, **any class-B data will be
> lost**. This is necessary to protect class-B data from attackers who can read the user's email
> but do not know the account password (**including those who compromise the IdP and the keyserver
> itself**).
> — [onepw protocol](https://mozilla.github.io/ecosystem-platform/explanation/onepw-protocol)

The reset endpoint is *"just like the /account/create API"* — **recovery implemented as
re-creation.** The fix is the recovery key: `resetPasswordWithRecoveryKey` decrypts the JWE to
recover the real `kB`, then re-wraps it under the new `unwrapBKey`.

One subtlety with direct consequences for any re-wrap design:

> any time kB or the password is changed, the authSalt should be changed too. Otherwise knowledge
> of both wrap(wrap(old-kB)) and old-kB would reveal wrapKey, making it easy to deduce the new kB.

**XOR/AEAD wrapping does not compose safely across key changes unless every layer's salt rotates
too.**

**7. Mistakes to avoid copying.** 1000-round PBKDF2 (and the lesson that **legacy KDF parameters
are effectively permanent** — Mozilla wrote the migration plan in 2014 and it is still at rollout
0). Email as the KDF salt (mutable identifier, no per-account randomness; they needed a dedicated
regression test for a primary-email swap). Unauthenticated XOR wrapping — there is deliberately no
MAC on `wrap(kB)`, because *"a MAC on kB would introduce an additional oracle to feed a dictionary
attack"*. And recovery-as-re-creation: the analogue here would be silently minting a *new* age
identity instead of recovering the old one, which is worse than an error because it looks like
success.

### Apple iCloud Keychain escrow

**1. What the human holds.** With 2FA, *"the device passcode is used to recover an escrowed
keychain"*; without, a six-digit iCloud Security Code, or a longer/random one by choice
([Secure iCloud Keychain recovery](https://support.apple.com/guide/security/secure-icloud-keychain-recovery-secdeb202947/web)).
Passcodes may be *"six-digit, four-digit, and arbitrary-length alphanumeric"*
([Passcodes and passwords](https://support.apple.com/guide/security/passcodes-and-passwords-sec20230a10d/web))
— **so the secret protecting the escrow can be ~13 bits.**

**2. Where it lives.** Double-wrapped, and the doubling is the point:

> The keybag is wrapped with the user's iCloud security code **and** with the **public key of the
> hardware security module (HSM) cluster** that stores the escrow record.

**3. Offline: no.** Recovery needs Apple Account + password, an SMS reply, the security code, and a
live quorum: *"If a majority agree, the cluster unwraps the escrow record and sends it to the
user's device."*

**4. Offline-attack surface: none, and that is the whole design.** From
[Escrow security for iCloud Keychain](https://support.apple.com/guide/security/escrow-security-for-icloud-keychain-sec3e341e75d/web):

> The HSM cluster verifies that a user knows their iCloud security code using the **Secure Remote
> Password (SRP)** protocol; **the code itself isn't sent to Apple.**

> The escrow service allows only **10 attempts** … **After the 10th failed attempt, the HSM cluster
> destroys the escrow record and the keychain is lost forever.** This provides protection against a
> brute-force attempt to retrieve the record, at the expense of sacrificing the keychain data in
> response.

> These policies are **coded in the HSM firmware**. **The administrative access cards that permit
> the firmware to be changed have been destroyed.** Any attempt to alter the firmware or access the
> private key causes the HSM cluster to **delete the private key**.

Apple deliberately **removed its own ability** to weaken the counter, converting a policy promise
into a physical one. The device-side analogue works the same way — *"The passcode or password is
entangled with the device's UID, so brute-force attempts need to be performed **on the device under
attack**"*, calibrated so *"one attempt takes approximately 80 milliseconds"*, with
Secure-Enclave-enforced escalating delays (1 min / 5 / 15 / 1 hr / 3 hrs / 8 hrs) and an optional
wipe at 10. 80 ms against a 6-digit PIN is ~22 hours of grinding; **the entropy is doing none of
the work, the counter is doing all of it.**

**5. Recovery.** Recovery contacts (a 256-bit AES key held by Apple, the encrypted packet held by
the contact — *"Neither the AES key nor the packet provides any information about the underlying
key by itself"* — redeemed over SPAKE2+ with an out-of-band code and a liveness check); a 28-character
recovery key; and under Advanced Data Protection at least one is **mandatory**, with *"If the
recovery methods fail … Apple can't help recover the user's end-to-end encrypted iCloud data."*

**6. The essential precondition, bluntly.** A short human secret is safe only when the adversary
cannot take more guesses than you allow — and enforcing that needs a third party that (a) holds the
ciphertext so no offline copy exists, (b) keeps monotonic state the attacker cannot roll back, and
(c) can destroy the ciphertext. **An offline design has none of these and cannot fake any of them.**
A counter stored beside the blob is a file the attacker snapshots first; a secure-element counter
binds to *that machine*, and the premise here is a machine that has never met the user.

**7. Mistakes to avoid copying.**

- **Destructive failure.** Burn-after-N is *"impossible by construction"*, which the map forbids —
  and against a copied blob it protects nothing anyway. Apple can afford it because escrow is a
  convenience over devices that still hold the keychain locally.
- **A short PIN without the counter.** Lifting "6-digit code" from Apple while dropping the HSM is
  not a simplification, it is total loss of security. This is the single most likely misreading of
  the Apple design.
- **Unverifiable operational assurance as a control.** "The cards were destroyed" is magnificent
  and completely unauditable. In a public repo, properties should be checkable from the artifacts.
- **Recovery paths that need a live third party** — SMS, a quorum, "call Apple Support to be
  granted more attempts". All unavailable offline.

### 1Password and Bitwarden

**1. What the human holds.** 1Password: a memorised account password **plus a Secret Key that is
carried, not memorised**. From the [whitepaper](https://1passwordstatic.com/files/security/1password-white-paper.pdf):

> Your Secret Key is generated on your computer when you first sign up, and is made up of a
> non-secret version setting, ("A3"), your non-secret Account ID, and a sequence of 26 randomly
> chosen characters. … This is uncrackable, but unlike your account password, isn't something
> you're expected to memorize or even type on a keyboard regularly.

Footnote 4 gives the exact entropy: *"Characters in the Secret Key are drawn uniformly from a set
of **31** uppercase letters and digits. With a length of 26, that gives us 31^26 which is just a
tad over 128 bits."* Note: **31 symbols, not base32**, and 34 non-hyphen characters of which only
26 are secret. The unlock key is now called the **AUK** (Account Unlock Key); "MUK" is the retired
name. It lives *"on your device by your 1Password client"* and in the printed Emergency Kit.

Bitwarden: **the master password alone**, salted with the email address
([security whitepaper](https://bitwarden.com/help/bitwarden-security-white-paper/)).

**2–3. Where it lives / offline.** Both server-side, both offline-capable **only on a device that
has already met the user**. 1Password: *"Depending on the completeness of the cached data, the
client may be able to function offline"* (§8.2.7). Bitwarden: *"Any unlocked Bitwarden app can be
used offline in read-only mode"* ([using Bitwarden offline](https://bitwarden.com/help/using-bitwarden-offline/)).
**Neither solves the roaming-to-a-virgin-machine problem except by making the human carry the
Emergency Kit.**

**4. The weak-secret mechanism — 2SKD, exactly.**

```
AUK = PBKDF2-HMAC-SHA256(password, HKDF(salt, email), 650000)
      XOR
      HKDF(SecretKey, salt = accountID, info = formatVersion)
```

650 000 iterations; accounts predating 2023-01-27 use fewer, and *"can be updated to the current
standard value by changing either the account password or Secret Key"* (footnote 14). The security
claim:

> Nothing 'crackable' is stored. … Even if he happens to make a correct guess, he won't know that
> he has guessed correctly. A correct guess will fail the same way an incorrect guess will fail
> without the Secret Key.

**That last sentence is the crisp statement of the property**: without the Secret Key there is *no
verification oracle at all*, so the attacker's search space is not "password entropy" but "password
entropy × 2^128".

Bitwarden is the control group: PBKDF2-SHA256 at **600 000** iterations (also the enforced minimum
since 2026.2.1), or opt-in Argon2id at **32 MiB / t=6 / p=4**
([KDF algorithms](https://bitwarden.com/help/kdf-algorithms/)). A stolen Bitwarden blob *is*
gridable at whatever entropy the human chose.

**Both vendors state that their KDF parameters are set by their weakest client, not by the threat
model.** 1Password: *"Because key derivation is performed by the client … we are constrained in our
choices by our least efficient client"* — which is why they still ship PBKDF2 in 2026. Bitwarden
caps Argon2id memory because *"Argon2id users with a KDF memory value higher than 64 MiB will
receive a warning dialogue every time iOS autofill is initiated"*. Neither constraint applies to a
once-per-login decrypt on a real machine.

**5. Recovery.** 1Password: *"The ability to recover or reset the account password or Secret Key
would give us (or an attacker who gets into our system) the ability to reset a password to
something known … **We therefore deny ourselves this capability.**"* Mitigations are all
pre-arranged: the Emergency Kit (recovers a *lost device*, not a *forgotten password* — the
whitepaper's own Story 2 makes this explicit), a Recovery Group (*"a copy of the vault key is
encrypted with the public key of the recovery group"*), and single-user recovery keys. Bitwarden:
*"Bitwarden has no way to access, retrieve, or reset your master password"*, with Emergency Access
(the grantor's User Symmetric Key encrypted to the grantee's RSA public key) and organization
account recovery.

**6. Password change.** Both are a single re-wrap, and both expose the expensive re-key as a
distinct, warned-about operation. See finding 5 for why 1Password's Appendix A.5 caveat is far
worse in git than it is for them. Bitwarden's own rotation hazards are worth reading before
designing one: *"Rotating your encryption key is a potentially dangerous operation"*, *"Making
changes in a session with a 'stale' encryption key will cause data corruption that will make your
data unrecoverable"*, and you must log out every client first
([account encryption key](https://bitwarden.com/help/account-encryption-key/)).

**7. Mistakes to avoid copying.**

- **Do not copy the KDF parameters.** They are weakest-client numbers, stated as such.
- **Do not copy the server-side second hash.** Bitwarden's extra 100 000 iterations buy
  authentication; with no server they buy nothing. 1Password admits deriving an auth secret costs
  them *"a 1-bit advantage"* to the attacker.
- **Do not copy 2SKD without deciding where the second secret lives.** Its entire claim rests on
  the Secret Key never leaving the device. Put it in the public repo and 2SKD degrades to plain
  PBKDF2 with a longer ceremony; require the human to carry it and you have reinvented the
  Emergency Kit — *a piece of paper in a bank vault*, which is exactly what a roaming user does not
  have at a seat that has never met them.
- **Do not copy "we deny ourselves this capability" without copying the pre-arranged escape
  hatch.** Every recovery path in both products is a second independent wrapping of the same key,
  established in advance, requiring nothing from the vendor.

### age / rage passphrase (scrypt) recipients

**Wire format**, from the [age v1 spec](https://github.com/C2SP/C2SP/blob/main/age.md):

```
-> scrypt ajMFur+EJLGaohv/dLRGnw 18
8SHBz/ldWnjyGFQqfjat6uNBarWqqEMDS7W8X7+Xq5Q
```

- salt: **16 bytes from a CSPRNG**, base64, fresh per stanza and per file;
- third argument: **base-two logarithm of the work factor**, decimal, `^[1-9][0-9]*$`;
- `wrap key = scrypt(N = work factor, r = 8, p = 1, dkLen = 32, S = "age-encryption.org/v1/scrypt" || salt, P = passphrase)` —
  **the label is prefixed, not appended**, giving a 44-byte scrypt salt. `r` and `p` are fixed by
  the spec; there is no wire field for them.
- `body = ChaCha20-Poly1305(key = wrap key, plaintext = file key)`, nonce fixed at twelve zero
  bytes. Decrypters MUST check the body is exactly 32 bytes *"to mitigate partitioning oracle
  attacks"*.

**Verified here**, age 1.3.1 — the header of an `age -p` file decodes to exactly that shape, with
work factor 18 and a 16-byte salt:

```
age-encryption.org/v1
-> scrypt +l/PCcieyJeGT3/l/HD6Xw 18
jdzhtNrLHmXgGxWIlaamxAxXdAQVq+MaSoMvVYn03lg
--- AD0tfWpF9o+xdaU/5kM69uwGVrz0RHZ9kS/8CG
```

**Parameters, from [`scrypt.go`](https://github.com/FiloSottile/age/blob/main/scrypt.go) at v1.3.1:**

| | Value | Source comment | Memory (`128·N·r`) |
| --- | --- | --- | --- |
| Encrypt default | `workFactor: 18` | *"1s on a modern machine"* | **256 MiB** |
| Decrypt cap | `maxWorkFactor: 22` | *"15s on a modern machine"* | **4 GiB** |
| Hard bounds | `logN > 30 \|\| logN < 1` panics | | |

**Measured here** (`hashlib.scrypt`, 8-core `x86_64-linux`): logN=17 → 128 MiB, 0.52 s; **logN=18 →
256 MiB, 1.03 s** (peak RSS 273 MiB); logN=14 → 16 MiB, 0.07 s. This matches age's own "1s"
comment, and it settles a number that is easy to get wrong: **age's default is 256 MiB, i.e. twice
OWASP's strongest scrypt line** (N=2^17, r=8, p=1 = 128 MiB).

Two hard limits with direct design consequences:

- **The CLI exposes no way to raise the work factor on encrypt.** The only hook in
  [`cmd/age/age.go`](https://github.com/FiloSottile/age/blob/main/cmd/age/age.go) is
  `testOnlyConfigureScryptIdentity`. You get 18, or you use the Go library / rage / a plugin.
- **The decrypt cap of 2^22 is a 4 GiB ceiling.** Whatever is chosen must be openable on the
  weakest seat in the fleet, so RAM at the seat — not attacker cost — is the binding constraint.

**Header exposure.** The header is plaintext: format version, **number of stanzas**, each stanza's
type tag and all arguments (so the salt and exact work factor are public — unavoidable, the
decrypter needs them), the 32-byte wrapped file key per stanza, and an HMAC-SHA-256 over the header
keyed by `HKDF(file key, "", "header")`. **You need the file key to rewrite a header**, so a rewrap
is only possible for a file you can already decrypt. `age-inspect(1)` reads all of this *"without
decrypting"*.

**No rotation.** The file key is per-file, 16 CSPRNG bytes, *"MUST NOT be reused across multiple
files"*, and *"the payload MUST NOT be modified without re-encrypting it as a new file with a fresh
nonce."* No `rewrap`/`rotate` command exists in either tool; adding a recipient means decrypt +
re-encrypt. For scrypt it is doubly impossible, since the stanza must be the only one.

**rage differs in one way that matters for roaming.** rage *benchmarks* the work factor rather than
fixing it — `/// Pick an scrypt work factor that will take around 1 second on this device.` — and
sets `max_work_factor = target_work_factor + 4` (*"roughly 16 seconds"*), with a doc comment
warning it *"might not be suitable for systems processing untrusted files"*. So a rage file's cost
depends on the encrypting machine and a rage decrypter's ceiling on the decrypting machine. **Go
age's fixed 18/22 is the more predictable choice for heterogeneous hardware** — and note Go age
will reject anything rage produced above 22. rage's only CLI knob is decrypt-side:
`--max-work-factor <WF>`.

Both tools autogenerate a strong passphrase when the human declines to supply one — age uses **10
words from the 2048-word BIP39 English list = 110 bits**
([`cmd/age/wordlist.go`](https://github.com/FiloSottile/age/blob/main/cmd/age/wordlist.go)).

**Mistakes to avoid.** Assuming a passphrase file can carry a recovery recipient (it cannot);
assuming rage and age agree on parameters (they do not); assuming the work factor can be raised
from the CLI (it cannot); and choosing a work factor against attacker cost rather than the weakest
seat's RAM.

---

## Current KDF guidance, and the gap between the two sources

**OWASP Password Storage Cheat Sheet** ([current](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)),
in its own stated order of preference — **Argon2id → scrypt → bcrypt (legacy) → PBKDF2 (FIPS)**:

| Algorithm | OWASP's numbers |
| --- | --- |
| **Argon2id** | m=47104 (46 MiB) t=1 p=1 · **m=19456 (19 MiB) t=2 p=1** · m=12288 t=3 p=1 · m=9216 t=4 p=1 · m=7168 t=5 p=1 — *"provide an equal level of defense"* |
| **scrypt** | **N=2^17 (128 MiB) r=8 p=1** · N=2^16 r=8 p=2 · N=2^15 r=8 p=3 · N=2^14 r=8 p=5 · N=2^13 r=8 p=10 |
| **bcrypt** | work factor ≥ 10; *"legacy systems"* only; 72-byte input limit |
| **PBKDF2** | HMAC-SHA256 **600 000** · HMAC-SHA512 220 000 · HMAC-SHA1 1 400 000 (legacy) |

**RFC 9106 §4** ([RFC 9106](https://www.rfc-editor.org/rfc/rfc9106.html#section-4)), verbatim:

> 1. If a uniformly safe option that is not tailored to your application or hardware is acceptable,
>    select Argon2id with **t=1 iteration, p=4 lanes, m=2^(21) (2 GiB of RAM), 128-bit salt, and
>    256-bit tag size**. This is the FIRST RECOMMENDED option.
> 2. If much less memory is available, a uniformly safe option is Argon2id with **t=3 iterations,
>    p=4 lanes, m=2^(16) (64 MiB of RAM)** … This is the SECOND RECOMMENDED option.

On variants: *"Argon2id works as Argon2i for the first half of the first pass over the memory and
as Argon2d for the rest, thus providing both side-channel attack protection and brute-force cost
savings"*, and *"Argon2id MUST be supported by any implementation of this document"*. Note the
nuance: RFC 9106 says Argon2**i** is *"preferred for password hashing and password-based key
derivation"* in isolation; Argon2id is mandatory because it *combines* both properties. OWASP's two
lowest-`t` rows are annotated *"(Do not use with Argon2i)"* for the same reason.

**The gap is the decision-relevant fact.** OWASP's top Argon2id line is 46 MiB; RFC 9106's FIRST
RECOMMENDED is 2 GiB — a factor of ~45. They are not in conflict; they answer different questions.
OWASP says so:

> If the work factor is too high, the performance of the application may be degraded, which could
> be used by an attacker to carry out a denial of service attack by exhausting the server's CPU
> with a large number of login attempts. … **As a general rule, calculating a hash should take less
> than one second.**

**That one-second rule is a server-throughput constraint, stated as one. Do not import it into a
once-per-login local unwrap.**

**On the public-ciphertext threat model specifically: neither source addresses it.** I searched
OWASP's source for `key derivation`, `encryption`, `offline`, `ciphertext`, `brute` — the page is
entirely about server-side storage for online verification and defers elsewhere: *"For further
guidance on encryption, see the Cryptographic Storage Cheat Sheet."* RFC 9106 comes closest with a
worked example, and it is a good analogy — full-disk encryption is precisely "attacker holds the
ciphertext indefinitely; decryption happens once at boot on the user's own hardware":

> Key derivation for hard-drive encryption, which takes 3 seconds on a 2 GHz CPU using 2 cores --
> Argon2id with 4 lanes and 6 GiB of RAM.

**But cite that carefully.** It is a latency-budget example, not a threat-model statement about
public ciphertext. Neither document says "raise the parameters because the ciphertext is public".

The only primary source in this survey that *does* speak to the public-blob threat model is
1Password's whitepaper, and **its answer is not "raise the KDF"** — it is 2SKD: add 128 bits of
non-memorised entropy, because no feasible KDF parameter rescues a low-entropy password from an
attacker holding the blob. That is finding 1 again, arriving from the parameter side.

---

## What this changes about the downstream question

Not decisions — [#108](https://github.com/palebluebytes/host-user-contract/issues/108) and the ADR
own those. But the survey narrows the space in four specific ways.

1. **"Make the weak password safe" is off the table offline.** Every mechanism that does it needs a
   counting third party or server-held entropy. #108's option *"one password, two derivations — is
   memory-hardness alone enough?"* has a primary-source answer: **no**, memory-hardness is a
   constant factor, and 1Password — the one vendor that faced exactly this threat model — did not
   solve it with a KDF.
2. **The correlation problem has a number.** The published `$y$j9T$` hash is **16 MiB / ~36 ms**
   (measured here), below OWASP's Argon2id floor. If one password does both jobs, that is the
   cheaper oracle and it sets the price regardless of how expensive the unlock KDF is. #108's
   framing is correct, and the asymmetry is larger than "one crack buys both" suggests — it is "the
   *cheap* crack buys both".
3. **Recovery is achievable offline, and its shape is settled by five independent implementations:**
   a second high-entropy wrapping of the same key, printed, pre-arranged, no third party. But
   **age's scrypt stanza forbids expressing it as a second recipient**, so it has to be two
   scrypt-wrapped copies of one identity, not one file with two paths. That is a concrete shape
   constraint on whatever seam #108 and the ADR land on.
4. **Rotation is where a public repo is genuinely worse than a breached server.** Everyone gets
   cheap password change from the immutable-data-key hierarchy, and everyone inherits 1Password's
   A.5 caveat with it. For them the old blob requires a breach; here it is in git history forever.
   So "you can always change your password" is *not* an adequate answer to compromise in this
   design, and any ADR that leans on it should say so explicitly.

One further observation the map may want: **the third-party premise is not binary.** The map's
premise is *offline baseline; network is optional strengthening* — and finding 1 says the entire
weak-secret-rescue class lives on the other side of that line. A design could be offline-correct
and *additionally* accept a carried factor (1Password's shape, a printed card) that costs nothing
at a seat with no network. That is the one bridge the prior art actually supports, and it is
neither "one password" nor "two remembered passwords" — it is one remembered secret plus one
carried one. Whether the north-star user tolerates carrying anything is a usability question this
survey cannot answer.

---

## What could not be verified

- **The 1Password whitepaper's revision date.** No date string in the extracted text; the most
  recent internal reference is 2023-01-27. Cite it as "the current version at that URL".
- **`support.1password.com/change-secret-key/` and `/offline/`** returned HTTP 403 to automated
  fetching. The Secret-Key-change and offline claims rest on the whitepaper alone.
- **Whether Mozilla's key-stretching v2 (650 000 iterations) is enabled in production.** The
  in-repo grouping rule carries `DEFAULT_ROLLOUT_RATE = 0.0` and the settings model comments the
  v1 branch as *"Typical state"*, but the live `featureFlags.keyStretchV2` value is server config.
- **Whether Mozilla's recovery-phone feature preserves `kB`.** The `recoveryPhones` table exists in
  the schema; no first-party statement was found, and the cryptography makes it hard to see how it
  could.
- **"Cloud Key Vault" as Apple's own term.** It appears nowhere in the Apple Platform Security
  guide pages read here — the guide says *"escrow service"* and *"HSM cluster"*. The name comes
  from a 2016 conference talk, i.e. not a first-party document.
- **fscrypt's behaviour on a forgotten custom passphrase.** Structurally unrecoverable, but that is
  inference from the wrapping design; the README never states it in those words. The closest
  first-party text is the destructive-operation warning on `fscrypt metadata destroy`.
- **`support.mozilla.org` and freedesktop.org rendered man pages** both refuse automated fetches
  (bot challenge / 403). SUMO claims here are cited via `web.archive.org` snapshots; systemd
  man-page text is quoted from the upstream DocBook XML in the systemd repo instead.
- **Timing and memory figures are from one machine** (8-core `x86_64-linux`, 2026-08-24). They are
  order-of-magnitude anchors, not benchmarks. Attacker hardware is not modelled at all.
