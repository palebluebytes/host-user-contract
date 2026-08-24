# What a desktop session needs unlocked, and how the login password reaches it

Research for [#106](https://github.com/palebluebytes/host-user-contract/issues/106), under map
[#104](https://github.com/palebluebytes/host-user-contract/issues/104).

**Question.** The map's premise is that delivering the user's **root age key** is what buys them
their application secrets. Checked against how a real Linux desktop actually stores and unlocks
secrets — and against whether *this* greeter can drive the path that already exists.

**This document does not write the ADR.** It answers one question the map needs first: are the root
key and the desktop keyring **one problem or two**.

Claims about upstream behaviour are cited to source files, read from the exact revisions nixpkgs
pins in this repo's `flake.lock` (`567a49d1913ce81ac6e9582e3553dd90a955875f`), extracted and read on
this machine on 2026-08-24: **greetd 0.10.3**, **gnome-keyring 50.0**, **kwallet-pam 6.7.3**,
**util-linux 2.42.2**. Claims about this repo cite files and line numbers on `main` at `f129bb8`.
Anything not directly read is marked *unverified*.

Line numbers are those of the extracted tarballs, which are the exact artefacts nixpkgs builds —
for greetd, `fetchFromSourcehut { owner = "~kennylevinsen"; repo = "greetd"; rev = "0.10.3"; hash =
"sha256-jgvYnjt7j4uubpBxrYM3YiUfF1PWuHAN1kwnv6Y+bMg="; }`. sr.ht answers automated requests with
HTTP 418, so the greetd links below could not be machine-checked; the content behind them was read
from that tarball.

---

## Verdict: two problems — and a third the map has already excluded

**They are two problems.** The login password already unlocks the desktop keyring, by a mechanism
that is entirely built, ships in nixpkgs, and needs no new cryptography and no change to
[ADR-0003](../adr/0003-no-secrets-beyond-the-credential.md). The contract would not be *handling a
secret* to use it — it would be handing the credential it already collects to PAM instead of
verifying it privately, which is what every other login program on the machine does.

**But solving it buys nothing for the case the map chose to answer.** `pam_gnome_keyring` unlocks a
keyring **file that already exists in the user's home**. At a seat that has never met the user,
`/home/<user>/.local/share/keyrings/login.keyring` does not exist; `provision` creates the account
with `useradd --create-home` and activates a home-manager generation. Auto-unlock at a stranger seat
therefore succeeds and yields an **empty** keyring: no wifi password, no saved browser login,
nothing. The unlock path works and there is nothing behind it.

**And the keyring holds less than the premise assumes.** On a stock GNOME seat a saved wifi password
does **not** go to the keyring — it goes to a root-owned plaintext file in `/etc`. Firefox and
Thunderbird use no keyring at all. Chromium and every Electron app keep the keyring only as a
*wrapping key* for their own private database, and fall back to a published constant when it is
absent. So even a perfect keyring unlock delivers a partial surface.

So the decomposition is three ways, not two:

| | what it is | status |
| --- | --- | --- |
| **(a) Unlock the local store** | login password → PAM → `pam_gnome_keyring` → login keyring | **Solved upstream, and the contract's greeter currently bypasses it.** No ADR-0003 change. |
| **(b) Deliver user-owned secrets to a seat that has never met the user** | the root age key | **Open. Untouched by (a).** This is the ADR. |
| **(c) Carry the runtime-mutable bulk between seats** | saved logins, OAuth tokens, session state | **Out of scope by the map's own choice — and (b) does not help**, because sops-nix is a one-way push from the repo. |

Fixing (a) is worth doing on its own merits — it closes a real defect today — but it is **not**
partial progress on (b), and the map should not bank it as such. Conversely (b), once built, does
not reach (c): the largest part of what a non-savvy user would *notice* roaming is in neither
bucket the ADR governs.

There is also a cheaper win hiding here that needs no key and no ADR: a user who declares their
NetworkManager profiles with `psk-flags = not-saved` gets their networks at every seat, typing each
PSK once per seat. For the north-star user that may be a bigger share of the felt experience than the
sops tree is.

---

## Headline findings

1. **The contract's greeter bypasses PAM completely.** greetd has a full, correct PAM
   implementation and would drive keyring auto-unlock for free; the contract's flow never reaches
   it. `contract-greeter-bind` prompts for the password itself, verifies it with `perl crypt`, and
   `exec`s the session through `runuser` — whose PAM stack, on NixOS, has `unixAuth = false` and no
   session registration. See [Finding A](#finding-a-the-greeter-bypasses-pam).

2. **NixOS already wires `pam_gnome_keyring` into the greetd PAM stack.** `security.pam.services.greetd.enableGnomeKeyring`
   defaults to `services.gnome.gnome-keyring.enable`. The module is *sitting in the stack the
   contract's greeter never runs*. See [Finding A](#finding-a-the-greeter-bypasses-pam).

3. **The production wiring cannot boot as shipped.** `contract.greeter.enable` sets
   `default_session.command` but not `default_session.user`, which nixpkgs defaults to `"greeter"`;
   `contract-greeter-provision` exits on `[ "$(id -u)" = 0 ]`. No conformance VM boots this path —
   every live-session VM uses greetd's `initial_session` instead. See
   [Finding B](#finding-b-no-conformance-test-boots-the-production-path).

4. **The same bypass silently breaks sops-nix's home-manager module** — the module the map's Notes
   treat as already working. It is not an activation script; it is a **systemd *user* unit**
   (`sops-nix.service`, `WantedBy=default.target`) that hard-fails without `XDG_RUNTIME_DIR`. The
   greeter's session gets no logind session, so no user manager, so the unit never runs — and
   home-manager activation prints *"User systemd daemon not running"* and exits 0. See
   [Finding C](#finding-c-sops-nix-hm-is-a-systemd-user-unit-not-an-activation-script).

5. **Auto-unlock hard-depends on auth and session running in the same `pam_handle_t`, in one
   process.** Both modules stash the password at auth via `pam_set_data` and retrieve it at
   `open_session` via `pam_get_data`. A program that authenticates by other means gets
   `password = NULL` and the keyring stays locked — gnome-keyring's source calls the split-process
   case *"hopeless"* in a comment. `pam_setcred`, contrary to folklore, is a **no-op stub** in both
   modules. See [How auto-unlock actually works](#how-auto-unlock-actually-works).

6. **The keyring is not where a desktop user's secrets live.** On stock GNOME the wifi PSK is a
   root-owned plaintext line in `/etc`, not a keyring item; Firefox and Thunderbird use no keyring at
   all and ship an unprotected key next to the data; Chromium and Electron apps keep only a wrapping
   key there and degrade to a published constant without it. See
   [What actually holds a desktop user's secrets](#what-actually-holds-a-desktop-users-secrets).

---

## Finding A: the greeter bypasses PAM

### greetd itself does the PAM dance correctly

greetd's session worker runs one `pam_handle_t` from authentication through session start
([`greetd/src/session/worker.rs`](https://git.sr.ht/~kennylevinsen/greetd/tree/0.10.3/item/greetd/src/session/worker.rs)):

```rust
let mut pam = PamSession::start(service, user, conv)?;   // :127
if authenticate {
    pam.authenticate(PamFlag::NONE)?;                     // :130
}
pam.acct_mgmt(PamFlag::NONE)?;                            // :132
pam.setcred(PamFlag::ESTABLISH_CRED)?;                    // :135
…
pam.open_session(PamFlag::NONE)?;                          // :222
let pamenvlist = pam.getenvlist()?;                        // :239
```

and then `fork`s, `setuid`s and `execve`s the session command with `envvec` — the comment at `:242`
explains the fork: *"PAM is weird and gets upset if you exec from the process that opened the
session, registering it automatically as a log-out."*

The password reaches PAM as a **conversation response**: `SessionConv` is documented in
[`greetd/src/session/conv.rs:4`](https://git.sr.ht/~kennylevinsen/greetd/tree/0.10.3/item/greetd/src/session/conv.rs)
as *"a PAM conversation implementation that forwards questions"* over the worker socket, mapping
`AuthMessageType::Secret` to the greeter's password prompt. So the typed password is what
`pam_unix.so` sets as `PAM_AUTHTOK`, and every `optional` module later in the auth stack —
`pam_gnome_keyring.so` among them — reads it with `pam_get_item`.

`authenticate` is `true` on exactly one path
([`greetd/src/context.rs`](https://git.sr.ht/~kennylevinsen/greetd/tree/0.10.3/item/greetd/src/context.rs)):

| entry point | `authenticate` | used by |
| --- | --- | --- |
| `create_session` (`:179`, `initiate(…, true, …)` at `:200`) | **true** | the greeter, over `GREETD_SOCK` |
| `start_greeter` → `start_unauthenticated_session` (`:118`, `:84`) | false | the greeter session itself |
| `start_user_session` (`:158`) | false | `initial_session` (autologin) |

`create_session` is reached only through the IPC protocol
([`greetd_ipc/src/lib.rs:55-89`](https://git.sr.ht/~kennylevinsen/greetd/tree/0.10.3/item/greetd_ipc/src/lib.rs)):
`CreateSession { username }` → `PostAuthMessageResponse { response }` (one per PAM conversation
message) → `StartSession { cmd, env }`.

### The contract's greeter uses none of it

`greeter.nix:280-283` wires greetd to the orchestrator:

```nix
services.greetd = {
  enable = true;
  settings.default_session.command = lib.mkDefault "${bindScript}/bin/contract-greeter-bind";
};
```

That command is greetd's **greeter** binary — `greeter_bin` in the table above, started with
`authenticate = false`. `contract-greeter-bind` then does its own thing (`greeter/bind.nix`):

```sh
printf 'password: ' >&2; stty -echo …; read -r password; …            # :67
printf '%s\n' "$password" | contract-greeter-auth "$src" "$username" … # :76
contract-greeter-provision "$username" … "$activation" "$tier" "$mode" # :136
exec contract-greeter-session "$username" "/home/$username" "$desktop" # :139
```

`greeter/auth.nix:37` verifies the password in-process:

```sh
computed=$(perl -e 'print crypt($ARGV[0], $ARGV[1])' "$password" "$stored")
```

and `greeter/session.nix:65-69` launches the desktop:

```sh
if [ "$(id -un)" = "$username" ]; then
  exec env HOME="$home" bash -c "$dcmd"
else
  exec runuser -u "$username" -- env HOME="$home" bash -c "$dcmd"
fi
```

**`GREETD_SOCK` is never opened.** Nothing in `greeter/` mentions PAM; the only occurrence of the
word in the repo is [ADR-0018](../adr/0018-greeter-runtime-flow.md)'s note that provisioning sets a
password so that *later* PAM consumers (a screen locker, `sudo`) work.

### `runuser` does not rescue it

`runuser(1)` (util-linux 2.42.2) is explicit: *"runuser does not ask for a password (because it may
be executed by the root user only) and it uses a different PAM configuration"*, and *"This version
of runuser uses PAM for **session management**"* — session only, never `pam_authenticate`. So there
is no `PAM_AUTHTOK` and no auth-stage stash for a session module to pick up.

On NixOS the `runuser` service is deliberately minimal
([`nixos/modules/security/pam.nix:2708-2711`](https://github.com/NixOS/nixpkgs/blob/567a49d1913ce81ac6e9582e3553dd90a955875f/nixos/modules/security/pam.nix)):

```nix
runuser = {
  rootOK = true;
  unixAuth = false;
  setEnvironment = false;
};
```

`startSession` is left at its default of `false`, and `startSession` is what puts `pam_systemd.so`
in the session stack (`pam.nix:1660-1664`). So the target user's session gets **no logind session,
no `XDG_SESSION_ID`, and no `XDG_RUNTIME_DIR` of their own**. Worse, since `runuser` without `-l`
sets only `HOME`/`SHELL`/`USER`/`LOGNAME`, the desktop inherits the **greeter's** `XDG_RUNTIME_DIR`
— a `0700` directory owned by another uid. (*Derived from module and man-page source; not observed
on a booted system, because the path does not boot — see Finding B.*)

### What NixOS already has waiting

The greetd module wires the keyring in by default
([`nixos/modules/services/display-managers/greetd.nix:76-82`](https://github.com/NixOS/nixpkgs/blob/567a49d1913ce81ac6e9582e3553dd90a955875f/nixos/modules/services/display-managers/greetd.nix)):

```nix
services.greetd.settings.default_session.user = lib.mkDefault "greeter";

security.pam.services.greetd = {
  allowNullPassword = true;
  startSession = true;
  enableGnomeKeyring = lib.mkDefault config.services.gnome.gnome-keyring.enable;
};
```

`enableGnomeKeyring` places `pam_gnome_keyring.so` `optional` in **three** stacks
(`nixos/modules/security/pam.nix`): auth (`:1267-1272`, no options), password (`:1486-1494`,
`use_authtok`), and session (`:1709-1717`, `auto_start`). `security.pam.services.<n>.kwallet.enable`
does the same for `pam_kwallet5.so` (`:1261-1266` auth, `:1705-1709` session, with
`force_run` when `kwallet.forceRun`), and there is a third, newer option — `oo7.enable`, backed by
`pkgs.oo7-pam` (`:681-687`) — for the Rust Secret Service reimplementation.

**The module a keyring unlock needs is already in the stack the contract's greeter declines to
run.**

### What would have to change

Two options, in increasing order of correctness.

**Option 1 — speak greetd's IPC (the correct fix).** Keep steps 1–7 exactly as they are, then
replace the `exec contract-greeter-session` at `bind.nix:139` with the IPC handshake on
`$GREETD_SOCK`: `CreateSession { username }`, answer the `Secret` auth message with the password
already in hand, then `StartSession { cmd: [contract-greeter-session …] }`. This is *replaying* the
credential, not storing a new one:

- The account already exists by then and already carries the same hash `auth` verified
  (`provision.nix:85-86`), so `pam_unix` succeeds — [ADR-0018](../adr/0018-greeter-runtime-flow.md)
  already requires this for screen-lock to work.
- greetd's worker then runs `setcred`, `open_session` and `getenvlist` for the *target* user, so the
  session gets a logind session, `XDG_RUNTIME_DIR`, a systemd user manager, and device ACLs — all of
  which the current path lacks.
- `pam_gnome_keyring` unlocks as a side effect, at zero marginal cost.
- **Data before code survives intact.** The eval-free authentication at step 3 still gates
  everything; PAM runs at step 8, after the decision has already been made on inert data. The PAM
  call is not the authorisation, it is the *session establishment*.
- Cost: `contract-greeter-bind` must run as a user that can both invoke `provision` (root) and reach
  `GREETD_SOCK`. That constraint already exists unacknowledged — see Finding B.

**Option 2 — talk to the keyring daemon directly (the narrow fix).** `gnome-keyring-daemon` exposes
the unlock without PAM. Its option table
([`daemon/gkd-main.c:141-145`](https://gitlab.gnome.org/GNOME/gnome-keyring/-/blob/50.0/daemon/gkd-main.c))
documents `--login` as *"Run by PAM for a user login. Read login password from stdin"* and
`--unlock` as *"Prompt for login keyring password, or read from stdin"*; `perform_unlock` calls
`read_login_password (STDIN)` at `:1059-1061`. The PAM module itself uses the same control socket
rather than any private interface — `get_control_file` (`:611-634`) resolves
`$GNOME_KEYRING_CONTROL/control`, falling back to `$XDG_RUNTIME_DIR/keyring/control`, and
`unlock_keyring` (`:668-700`) sends `GKD_CONTROL_OP_UNLOCK` with the password as `argv[0]`.

Option 2 is a smaller diff but it is **strictly worse**: it hardcodes GNOME (kwallet needs an
entirely different dance — see below), it needs `XDG_RUNTIME_DIR` which the current path does not
have, and it leaves the session without logind. It also puts the contract in the business of piping
a password to a secret daemon, which is much closer to "the contract handles a secret" than
answering a PAM prompt is.

---

## Finding B: no conformance test boots the production path

`greeter.nix` sets `default_session.command` and nothing else. nixpkgs sets
`default_session.user = lib.mkDefault "greeter"`, and nothing in this repo, `examples/fleet`, or the
conformance suite overrides it. `greeter/provision.nix:54` is:

```sh
[ "$(id -u)" = 0 ] || { echo "provision: must run as root" >&2; exit 1; }
```

So a real `contract.greeter.enable` boot reaches step 7 as uid `greeter` and dies. Nothing catches
this, because the two families of test each exercise half the path:

| VM | posture | what it proves |
| --- | --- | --- |
| `conformance/greeter-session-vm.nix`, `-sequence-vm`, `-desktop-vm` | `autologin = "alice"` → greetd **`initial_session`** (`conformance/seat-vm.nix:79-82`) | the session launcher resolves and execs a real desktop — *inside a PAM session greetd opened*, which the production path never gets |
| `conformance/bind-loop-vm.nix`, `examples/fleet/integration-vm.nix` | `autologin = null` → `systemd.services.greetd.wantedBy = mkForce []`; the orchestrator is driven by hand via `machine.succeed(…)`, i.e. **as root** | the orchestrator's logic end-to-end — with the privilege and environment question assumed away |
| `conformance/greeter.nix:224-228` | eval-only | that `default_session.command` *contains the string* `contract-greeter-bind` |

The eval check asserts the wiring exists; no check asserts it can run. This is the repo's own
*"a missing check reads exactly like a passing one"* invariant (`CONTEXT.md:357`) landing on the
greeter itself.

Note the shape of the gap, because it is the same shape as the PAM bypass: the live-session VMs work
precisely **because** `initial_session` makes greetd open a PAM session for the target user. The
production path removes exactly that, and no test noticed.

---

## Finding C: sops-nix HM is a systemd *user* unit, not an activation script

The map's Notes take as settled that *"secrets-in-repo plus sops-nix's home-manager module already
works"*. That is true of a declaratively-bound user with an ordinary logind session. It is **not**
true through this greeter, and the failure is silent.

The home-manager module
([`modules/home-manager/sops.nix`](https://github.com/Mic92/sops-nix/blob/master/modules/home-manager/sops.nix))
does **not** decrypt during activation. It installs a user unit (`:380-393`):

```nix
systemd.user.services.sops-nix = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  Unit.Description = "sops-nix activation";
  Service = { Type = "oneshot"; …; ExecStart = script; };
  Install.WantedBy =
    if cfg.gnupg.home != null then [ "graphical-session-pre.target" ] else [ "default.target" ];
};
```

and the activation entry (`:408-434`) only *restarts* it, guarded:

```sh
systemdStatus=$(${systemctl} --user is-system-running 2>&1 || true)
if [[ $systemdStatus == 'running' || $systemdStatus == 'degraded' ]]; then
  ${systemctl} restart --user sops-nix
else
  echo "User systemd daemon not running. Probably executed on boot where no manual start/reload is needed."
fi
```

sops-nix's README states the same: *"The home-manager module requires systemd/user as it runs a
service called `sops-nix.service` rather than an activation script"*
([README.md](https://github.com/Mic92/sops-nix/blob/master/README.md)).

The runtime dir is mandatory with **no fallback**
([`pkgs/sops-install-secrets/linux.go:14-20`](https://github.com/Mic92/sops-nix/blob/master/pkgs/sops-install-secrets/linux.go)):

```go
func RuntimeDir() (string, error) {
	rundir, ok := os.LookupEnv("XDG_RUNTIME_DIR")
	if !ok {
		return "", fmt.Errorf("$XDG_RUNTIME_DIR is not set")
	}
	return rundir, nil
}
```

Put that against Finding A. `provision.nix:111` runs activation as
`runuser -u "$username" -- env HOME="$home" "$activation/activate"`, in a context with no user
systemd manager for that uid. So:

1. Activation hits the `else` branch, prints *"User systemd daemon not running"*, **exits 0**.
2. The session launches, still with no user manager.
3. `sops-nix.service` never runs. No secret is ever materialized.
4. Nothing reports an error.

**The greeter's session launch already breaks the module the map is building on — before the key
question is even reached.** Whatever ADR-0003 decides, Option 1 in Finding A is a prerequisite for
sops-nix HM to function at a greeter seat at all.

---

## How auto-unlock actually works

Both modules follow the same two-stage shape, and the shape is what decides whether a login program
can drive them.

### `pam_gnome_keyring.so`

From [`pam/gkr-pam-module.c`](https://gitlab.gnome.org/GNOME/gnome-keyring/-/blob/50.0/pam/gkr-pam-module.c)
(gnome-keyring 50.0):

- **`pam_sm_authenticate` (`:851`)** — `pam_get_item (ph, PAM_AUTHTOK, …)` at `:879`. If there is no
  password it logs *"no password is available for user"* and returns `PAM_SUCCESS` (a no-op). With a
  password it calls `unlock_keyring`; if the daemon is not yet running it either starts it with the
  password (`auto_start`) or **stashes the password for the session stage** (`:895-896`):
  ```c
  ret = stash_password_for_session (ph, password);
  syslog (GKR_LOG_INFO, "gkr-pam: stashed password to try later in open session");
  ```
- **`pam_sm_open_session` (`:904`)** — retrieves it (`:928`):
  ```c
  if (pam_get_data (ph, "gkr_system_authtok", (const void**)&password) != PAM_SUCCESS) {
  ```
  and the comment immediately below is the whole finding in the upstream's own words:
  > *No password, no worries, maybe this (PAM using) application didn't do authentication, or is
  > hopeless and wants to call different PAM callbacks from different processes.*

  `password` is set to `NULL`. With `auto_start` the daemon is still started — but with a `NULL`
  password, so **the login keyring stays locked** and the user is prompted for it later by the
  desktop, out of context.
- **`pam_sm_setcred` (`:959`)** is a bare `return PAM_SUCCESS;` — nothing depends on it.
- **`pam_sm_chauthtok`** rekeys the keyring when the login password changes, which is what the
  `use_authtok` entry in the NixOS *password* stack is for.

Two consequences the contract must respect:

- `pam_set_data`/`pam_get_data` are keyed on the `pam_handle_t`. **Auth and session must be the same
  handle in the same process.** greetd's worker satisfies this by construction; a program that
  authenticates in one process and launches in another does not.
- Unlocking is `GKD_CONTROL_OP_UNLOCK` over a **unix socket**, not a private ABI — which is what
  makes Option 2 above possible at all.

The login keyring's file format is password-derived and **weak**.
`gkm_secret_binary_write`
([`pkcs11/secret-store/gkm-secret-binary.c:589`](https://gitlab.gnome.org/GNOME/gnome-keyring/-/blob/50.0/pkcs11/secret-store/gkm-secret-binary.c))
picks `hash_iterations = g_random_int_range (1000, 4096)`, and `encrypt_buffer` (`:345`) uses
AES-128-CBC with key and IV both from
`egg_symkey_generate_simple (GCRY_CIPHER_AES128, GCRY_MD_SHA256, …)` over an **8-byte** salt. That
function ([`egg/egg-symkey.c:103`](https://gitlab.gnome.org/GNOME/gnome-keyring/-/blob/50.0/egg/egg-symkey.c))
is **not PBKDF2** — it is an OpenSSL `EVP_BytesToKey`-style iterated digest. Compare kwallet's
PBKDF2-HMAC-SHA512 at 50 000 iterations over a 56-byte salt.

Worse, there are two on-disk formats and the choice is silent
([`gkm-secret-collection.c:909-913`](https://gitlab.gnome.org/GNOME/gnome-keyring/-/blob/50.0/pkcs11/secret-store/gkm-secret-collection.c)):

```c
master = gkm_secret_data_get_master (self->sdata);
if (master == NULL || gkm_secret_equals (master, NULL, 0))
        res = gkm_secret_textual_write (self, self->sdata, &data, &n_data);
else
        res = gkm_secret_binary_write (self, self->sdata, &data, &n_data);
```

**An empty master password writes the keyring in cleartext.** And even encrypted, the keyring label
and every item's *attribute names* sit in the plaintext header
([`docs/file-format.txt`](https://gitlab.gnome.org/GNOME/gnome-keyring/-/blob/50.0/docs/file-format.txt)).

**This is not a place to put a root age key.** It is sized for "keep saved wifi passwords off a
stolen disk", it is only as strong as the login password, and it silently becomes plaintext if that
password is empty.

One more thing the spec forecloses: **there is no Secret Service API by which a client hands a
password to the service.** `Unlock()` takes object paths and returns a `Prompt` path to act on
([unlocking](https://specifications.freedesktop.org/secret-service/latest/unlocking.html)); credential
entry happens inside the service's own prompter. That is *why* PAM auto-unlock exists as an
out-of-band side channel through a private control socket rather than as part of the API. Any design
that wants to unlock without a human must use that side channel or PAM — the standard interface does
not offer the option.

### `pam_kwallet5.so`

From [`pam_kwallet.c`](https://invent.kde.org/plasma/kwallet-pam/-/blob/v6.7.3/pam_kwallet.c)
(kwallet-pam 6.7.3) the split is even starker:

- **`pam_sm_authenticate` (`:240`)** does **no unlocking at all**. It reads `PAM_AUTHTOK` (`:274`),
  prompts itself if empty (`prompt_for_password`, `:284`), `strdup`s it into
  `pam_set_data (pamh, kwalletPamDataKey, key, cleanup_free)` (`:308`) and returns **`PAM_IGNORE`**.
  It refuses outright for uid 0 (`:269-272`).
- **`pam_sm_open_session` (`:529`)** does the work: `pam_get_data` for the stashed password (`:567`)
  — and if it is missing, logs *"open_session called without <key>"* and returns `PAM_IGNORE` — then
  derives the wallet key and starts the daemon:
  ```c
  error = gcry_kdf_derive(passphrase, strlen(passphrase),
                          GCRY_KDF_PBKDF2, GCRY_MD_SHA512,
                          salt, KWALLET_PAM_SALTSIZE,
                          KWALLET_PAM_ITERATIONS, KWALLET_PAM_KEYSIZE, key);   // :817-820
  ```
  with `KWALLET_PAM_ITERATIONS 50000`, `KWALLET_PAM_SALTSIZE 56`, `KWALLET_PAM_KEYSIZE 56`
  (`:57-59`). The derived key is handed to `kwalletd --pam-login <pipefd> <sockfd>` (`:412`) over a
  pipe (`:521`), never through the filesystem, and `PAM_KWALLET5_LOGIN` is `pam_putenv`'d so a second
  invocation short-circuits (`:69`, `:243-246`).
- It also **skips unless the session is graphical** unless `force_run` is set (`:540-543`) — which is
  exactly what `security.pam.services.<n>.kwallet.forceRun` exists for.

kwallet's KDF (PBKDF2-SHA512 × 50 000) is substantially stronger than gnome-keyring's, for whatever
that is worth to a future decision.

### What the login manager must therefore do

**`pam_setcred` is a red herring.** The folklore requirement that the login program must call it is
false for both modules: `pam_sm_setcred` is a bare `return PAM_SUCCESS;` stub in gnome-keyring
(`gkr-pam-module.c:958-962`, and identically so as far back as `GNOME_KEYRING_2_30_3`) and in
kwallet-pam (`pam_kwallet.c:592-597`). The real requirements are narrower and harder:

1. **Be the PAM application.** Run the **auth** stack for the target user so an earlier module
   (`pam_unix.so`) populates `PAM_AUTHTOK`. Only a *module* may read it — *"Only a service module is
   privileged to read the authentication tokens, PAM_AUTHTOK and PAM_OLDAUTHTOK"*
   ([`pam_get_item(3)`](https://github.com/linux-pam/linux-pam/blob/master/doc/man/pam_get_item.3.xml)).
   Ordering matters: the keyring module must come *after* whatever authenticates.
2. **Run `pam_open_session` on the *same* `pam_handle_t`, in the same process**, privileged enough
   that `geteuid() == 0` ([`pam_open_session(3)`](https://github.com/linux-pam/linux-pam/blob/master/doc/man/pam_open_session.3.xml)).
   `pam_set_data`/`pam_get_data` live in the handle; there is no filesystem or D-Bus representation
   of it. Authenticating in one process and opening the session in another is the case
   gnome-keyring's source calls *"hopeless"*.
3. **Have `pam_systemd.so` in the session stack, before the keyring modules.** It is a session-only
   module that creates `/run/user/$UID` and sets `$XDG_RUNTIME_DIR`
   ([`pam_systemd(8)`](https://www.freedesktop.org/software/systemd/man/latest/pam_systemd.html)) —
   which is precisely what `get_control_file()` and `start_kwallet()` need to find their sockets.
4. **`fork`, then `execve` the session with `pam_getenvlist()` as its environment.**
   [`pam_getenvlist(3)`](https://github.com/linux-pam/linux-pam/blob/master/doc/man/pam_getenvlist.3.xml)
   says it outright: *"It is by design, and not a coincidence, that the format and contents of the
   returned array matches that required for the third argument of the `execle(3)` function call."*
   There is **no automatic inheritance** — `pam_putenv` writes into the handle and nowhere else.
   GDM does exactly this (`gdm_session_worker_get_environment()` is literally
   `return pam_getenvlist (worker->pam_handle);`, then `gdm_session_execute (…, environment, TRUE)`,
   [`gdm-session-worker.c`](https://gitlab.gnome.org/GNOME/gdm/-/blob/main/daemon/gdm-session-worker.c));
   so do SDDM ([`PamHandle::getEnv`](https://github.com/sddm/sddm/blob/develop/src/helper/backend/PamHandle.cpp))
   and util-linux `login`
   ([`login.c`](https://github.com/util-linux/util-linux/blob/master/login-utils/login.c)).
   Forking without honouring `pam_getenvlist()` gives the session nothing.

greetd satisfies all four (`worker.rs:127`, `:222`, `:239`, `:242`; `pam_systemd` arrives via
`security.pam.services.greetd.startSession = true`). The contract's greeter satisfies none of them.

For kwallet there is a **fifth** requirement that lives outside PAM entirely: the graphical session
must run
[`pam_kwallet_init`](https://invent.kde.org/plasma/kwallet-pam/-/blob/master/pam_kwallet_init),
which is `env | socat STDIN UNIX-CONNECT:$PAM_KWALLET5_LOGIN`, from
`plasma-kwallet-pam.service` (`PartOf=graphical-session.target`). `ksecretd` blocks in `accept()`
holding the unlocked wallet until that arrives. So a session that inherits `PAM_KWALLET5_LOGIN` but
does not start the Plasma session units still ends up with a wallet nobody can reach.

### And what the user sees when it does not happen

gnome-keyring distinguishes the two failure modes in its own prompt text
([`pkcs11/wrap-layer/gkm-wrap-prompt.c:519`](https://gitlab.gnome.org/GNOME/gnome-keyring/-/blob/50.0/pkcs11/wrap-layer/gkm-wrap-prompt.c)):

- *"The password you use to log in to your computer no longer matches that of your login keyring."*
  — PAM ran, supplied a password, and it was **rejected**.
- *"The login keyring did not get unlocked when you logged into your computer."*
  — PAM **never supplied one**. **This is the string a contract greeter user would see today.**

That is the concrete cost of Finding A, in the words the person actually reads. (There is a
self-healing path: once they type the correct keyring password,
`fix_login_keyring_if_unlock_failed()` rewrites the keyring credential to match the login password —
but only in the *mismatch* case, and only after a manual unlock.)

---

## What actually holds a desktop user's secrets

The premise worth testing is that the keyring is where a desktop user's secrets live. **It is not.**
The Secret Service covers substantially less than the name suggests, and the single item most worth
declaring — the wifi password — is by default not in it at all.

| Item | Where it actually lives | Declarable in a repo? |
| --- | --- | --- |
| **Wifi PSK / 802.1x / VPN — GNOME default** | **system-wide, root-owned plaintext** in `/etc/NetworkManager/system-connections/*.nmconnection`, mode `0600` | **Yes — the one clean case** |
| **Wifi PSK — KDE default** | Secret Service, agent-owned, via QtKeychain | profile yes, secret no |
| **Firefox saved logins** | **private**: `logins.json` + `key4.db`; **no keyring integration at all** | no |
| **Thunderbird mail passwords** | **private**, same NSS engine as Firefox | account definitions yes, secret no |
| **Chromium / Chrome logins** | **private SQLite**, whose column key is wrapped in the Secret Service; degrades to a published constant | no |
| **Evolution / evolution-data-server** | **Secret Service** (libsecret is a hard dependency) | `.source` account files yes, secret no |
| **KMail / Akonadi** | QtKeychain → Secret Service | account config yes, secret no |
| **SSH private keys** | **private files** in `~/.ssh`; gnome-keyring's agent is **off by default** since 48.0 | key files yes, unlocked state no |
| **GPG private keys** | **private**, `~/.gnupg/private-keys-v1.d/`; gnome-keyring **dropped** its GPG agent | key material yes, passphrase cache no |
| **GNOME Online Accounts** | Secret Service | no |
| **Nextcloud / Signal / Element** | Secret Service, via QtKeychain or Electron `safeStorage` | no |

### NetworkManager: system-wide, root-owned, and the only declarable seam

There is **no per-user NetworkManager profile store**. Profiles live in
`/etc/NetworkManager/system-connections/`, `/usr/lib/NetworkManager/system-connections/` and
`/run/NetworkManager/system-connections/`, all system-wide. The keyfile reference is blunt about
what is in them: *"For security, it will ignore files that are readable or writable by any user
other than 'root' since private keys and passphrases may be stored in plaintext inside the file"*
([nm-settings-keyfile](https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html)) — and
`nms-keyfile-writer.c` writes them mode `0600`, root-owned, with the PSK as a literal `psk=` line.

Every secret property has a paired `*-flags`
([`NMSettingSecretFlags`](https://networkmanager.dev/docs/api/latest/secrets-flags.html)):

- `NONE` (`0x0`) — *"The system is responsible for providing and storing this secret."* → plaintext
  in `/etc`.
- `AGENT_OWNED` (`0x1`) — *"A user-session secret agent is responsible for providing and storing
  this secret."* → keyring/wallet, never written to `/etc`.
- `NOT_SAVED` (`0x2`) — ask the user every time.
- `NOT_REQUIRED` (`0x4`).

**The default is `NONE`**, hardcoded in the macro that defines every secret-flags property
(`_nm_setting_property_define_direct_secret_flags`,
[`nm-setting-private.h`](https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/blob/main/src/libnm-core-impl/nm-setting-private.h)).
The desktops diverge on what they do with that:

- **GNOME** leaves the default. Its agent
  ([`shell-network-agent.c`](https://gitlab.gnome.org/GNOME/gnome-shell/-/blob/main/src/shell-network-agent.c))
  refuses to store anything else — `if (secret_flags != NM_SETTING_SECRET_FLAG_AGENT_OWNED) return;`
  — so a wifi password saved in a stock GNOME session lands in `/etc`, **not** in the keyring. The
  user only gets keyring storage by explicitly picking *"Store the password only for this user"*
  ([libnma `nma-ui-utils.c`](https://gitlab.gnome.org/GNOME/libnma/-/blob/main/src/nma-ui-utils.c)).
- **KDE** opts in when it can:
  `SecretFlags secretFlags = QKeychain::isAvailable() ? AgentOwned : None;`
  ([plasma-nm `secretagent.cpp`](https://invent.kde.org/plasma/plasma-nm/-/blob/master/kded/secretagent.cpp)).

This is the one place where "declare it in the repo" genuinely works, and NetworkManager already
ships the seam: put the profile in `/usr/lib/NetworkManager/system-connections/` and set
`psk-flags` to `agent-owned` or `not-saved` so the declared profile deliberately carries **no**
secret.

### Firefox and Thunderbird: a private store that protects nothing

`logins.json` is encrypted through NSS's Secret Decoder Ring, whose key lives in `key4.db` **in the
same profile directory**. With no Primary Password set — the default — that key is wrapped with the
empty password, and NSS says so on purpose:

> *"check to see if we have the NULL password set. We special case the NULL password so that if you
> have no password set, you don't do thousands of hash rounds. This allows us to startup and get
> webpages without slowdown in normal mode."*
> — [`lib/softoken/sftkpwd.c`](https://github.com/nss-dev/nss/blob/master/lib/softoken/sftkpwd.c)

So `logins.json` + `key4.db` copied together are trivially decryptable. There is no Secret Service
integration and no near prospect of one: [bug 309807](https://bugzilla.mozilla.org/show_bug.cgi?id=309807)
(*"Integrate Password Manager with Gnome Keyring Manager"*, filed 2005) was closed as a duplicate in
2016 of [bug 1586072](https://bugzilla.mozilla.org/show_bug.cgi?id=1586072), which is still
**UNCONFIRMED**. Thunderbird uses the same engine
([`MsgIncomingServer.sys.mjs`](https://github.com/thunderbird/thunderbird-desktop/blob/main/mailnews/base/src/MsgIncomingServer.sys.mjs)).

### Chromium: the keyring holds a wrapping key, not the secrets

Chromium keeps logins in its own `Login Data` SQLite with an encrypted `password_value` BLOB
([`login_database.cc`](https://chromium.googlesource.com/chromium/src/+/HEAD/components/password_manager/core/browser/password_store/login_database.cc));
URLs and usernames are in the clear. The Secret Service holds **one** 16-byte secret, from which the
column key is derived
([`freedesktop_secret_key_provider.h`](https://chromium.googlesource.com/chromium/src/+/HEAD/components/os_crypt/async/browser/freedesktop_secret_key_provider.h)).
`--password-store=` accepts `gnome-libsecret | kwallet | kwallet5 | kwallet6 | basic`, autodetects
by desktop environment, and *"will fall back to `basic` if a requested or autodetected store is not
available"*
([password_storage.md](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/linux/password_storage.md)).

`basic` is a published constant, spelled out in the source
([`posix_key_provider.cc`](https://chromium.googlesource.com/chromium/src/+/HEAD/components/os_crypt/async/browser/posix_key_provider.cc)):

```cpp
// PBKDF2-HMAC-SHA1(1 iteration, key = "peanuts", salt = "saltysalt")
constexpr auto kV10Key = std::to_array<uint8_t>({0xfd, 0x62, …});
```

**This is the shape most desktop secret storage takes**, and it matters for any design here: the
keyring is a *key-wrapping* service for private stores, not the store itself. Electron says the same
in its own docs — backends are `kwallet*` / `gnome_libsecret` / `basic_text`, and
***"If no secret store is available, items stored using the `safeStorage` API will be unprotected as
they are encrypted via hardcoded plaintext password"***
([safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage)).

Two apps care enough to defend against it, and their defence is directly hostile to roaming:
**Signal Desktop pins the backend** and throws `SafeStorageBackendChangeError` if the detected one
differs from what it recorded
([`app/main.main.ts`](https://github.com/signalapp/Signal-Desktop/blob/main/app/main.main.ts)), and
**Element Desktop** keeps a `safeStorageBackendMap` so it can force the same `--password-store`
across restarts ([`src/store.ts`](https://github.com/element-hq/element-desktop/blob/develop/src/store.ts)).
**The identity of the Secret Service backend is itself persisted per-machine state that these apps
will refuse to run without.** A user roaming between a GNOME seat and a KDE seat trips this.

### An aside worth knowing: KWallet now sits *behind* the Secret Service

The KWallet framework has been restructured. Its README states that *"kwalletd exposes the KWallet
API and proxies it to Secret Service, it can use ksecretd or any other Secret Service provider"* and
that *"ksecretd is the codebase that used to be kwalletd, but now exposes only the Secret Service
API"* ([README](https://invent.kde.org/frameworks/kwallet/-/blob/master/README.md)). `ksecretd`
claims `org.freedesktop.secrets` when `[org.freedesktop.secrets] apiEnabled` is set — and that
setting **defaults to `true`**
([`kwalletsettings.kcfg`](https://invent.kde.org/frameworks/kwallet/-/blob/master/src/kwalletsettings.kcfg)),
so it is opt-*out*. Note the consequence for a seat that runs both stacks: whichever of
`gnome-keyring-daemon` and `ksecretd` starts first takes the bus name. **There is no arbitration.**

---

## What is genuinely runtime-mutable

Sorting the surface by how an entry comes into existence is what decides whether declaring it in a
repo is even coherent.

**Created by ordinary desktop use, and not declarable by any means:**
saved browser logins (Firefox, Chromium), GNOME Online Accounts OAuth tokens, Signal/Element/Nextcloud
session credentials, mail passwords, and the Chromium/Electron wrapping keys themselves. These are
the bulk of the surface. A person acquires them by clicking "save"; there is no earlier moment at
which a repo could have known them.

**Declarable, with the secret held back:** NetworkManager profiles — SSID, security type, autoconnect
policy, 802.1x identity — with `psk-flags = agent-owned` or `not-saved`. Account *definitions* are
similarly declarable everywhere: Evolution `.source` files, Thunderbird/KMail account config, SSH
`config` and public keys.

**Declarable including the secret, if a key is available:** anything a user is willing to put in a
sops file — API tokens, a signing key, a wifi PSK they are content to have in `/etc` at every seat.
This is the category ADR-0003's reopening is actually about, and note that it is the *smallest* of
the three.

Two asymmetries follow, and both cut against the map's framing:

1. **The runtime-mutable bulk cannot be made declarative, so it can only ever be made to *roam*.**
   That is the sync problem the map explicitly puts out of scope. Delivering the root key does not
   touch it: sops-nix is a one-way push from the repo (see below), so a login saved on Tuesday is not
   in the repo on Wednesday.
2. **The declarable-without-secret category needs no key at all.** A user who declares their wifi
   profiles with `psk-flags = not-saved` gets their networks at every seat and types the PSK once per
   seat — with no root key, no ADR change, and no new mechanism. For the non-savvy user this may be a
   larger share of the felt experience than the sops tree is.

---

## sops-nix and the Secret Service: they compose, but only one way

They do not overlap and they do not compete. They **compose in one direction only**, and the
direction is the wrong one for a roaming user.

**sops-nix HM has exactly one output surface: files.** Grepped across the tree at
`a8627b21b9107c5711c96b84f32a9a4b3d45295f`, there is no D-Bus client, no libsecret binding, no
`SecretItem`. The only `keyring` symbol in the Go source is `setupGPGKeyring` — a temporary *GnuPG*
home. Output is `os.WriteFile` for secrets, `os.CreateTemp`+rename for templates, and
`os.Symlink`/`os.Rename` for the generation pointer
([`pkgs/sops-install-secrets/main.go`](https://github.com/Mic92/sops-nix/blob/master/pkgs/sops-install-secrets/main.go)).

**It is a one-way push, structurally.** Each run allocates a fresh generation directory
(`prepareSecretsDir`, `main.go:404-441`), re-materializes every secret from the encrypted source,
atomically swaps the symlink (`atomicSymlink`, `:759-789`) and prunes older generations
(`pruneGenerations`, `:793-833`; the HM default is `keepGenerations = 1`). Anything an application
wrote into generation *N* is simply absent from *N+1*. There is no re-encrypt path in the repo at
all: adding a secret means editing the encrypted file on the **encrypting** side and re-running
activation. Recipients are likewise fixed at encryption time — `sops updatekeys`
([`cmd/sops/main.go`](https://github.com/getsops/sops/blob/main/cmd/sops/main.go)) runs against
`.sops.yaml`, on the repo side, never on the host.

**The Secret Service is the opposite kind of thing.** Its whole point is `CreateItem` at runtime
([spec](https://specifications.freedesktop.org/secret-service/latest/)), reached through
[libsecret](https://gnome.pages.gitlab.gnome.org/libsecret/), *"a Secret Service D-Bus client
library"*. Saving a wifi password is a `CreateItem`.

So the composition is:

- **sops → keyring: possible, and there is upstream prior art.** Every existing bridge implements
  the Secret Service **server** over a file backend:
  [`pass-secret-service`](https://github.com/grimsteel/pass-secret-service) (*"an implementation of
  `org.freedesktop.secrets` using `pass`"*),
  [`pass_secret_service`](https://github.com/mdellweg/pass_secret_service),
  [KeePassXC's FdoSecrets plugin](https://github.com/keepassxreboot/keepassxc/blob/develop/src/fdosecrets/README.md),
  and [`oo7`](https://github.com/bilelmoussaoui/oo7) (whose `pam/` component is the `oo7-pam` NixOS
  already offers). A sops-backed collection would fit the same shape.
- **keyring → sops: no prior art, and none is possible without the repo.** Nothing upstream writes
  runtime items back into an encrypted tree, because the write side needs the recipient set and the
  `.sops.yaml` — both of which live in the git repo, not on the seat.

There is one genuinely useful, small composition available today: **sops-nix materializes a
passphrase file, and that file is piped into `gnome-keyring-daemon --unlock`.** That works because
`--unlock` reads a *password* from stdin. It is not key-file unlocking — gnome-keyring has **no**
asymmetric or key-file unlock mode, and no keyring-import facility (`tool/gkr-tool-import.c` imports
certificates and PGP/private keys into PKCS#11, not `.keyring` files). It is also circular for our
purposes: it presumes the age key already arrived.

Two further properties matter for any design built on sops-nix HM:

- **No intra-user isolation.** The HM module has no `owner`/`group` options — those exist only in the
  NixOS module — because *"features like the creation of the ramfs and changing the owner of the
  secrets are not available for non-root users"* (README). Every secret is mode `0400`, owned by the
  one user. Any process running as that user reads all of them. A keyring, by contrast, at least has
  a prompt-and-confirm story per application.
- **The age private key is copied in cleartext into the runtime dir on every run.**
  `main.go:1400-1439` builds `$XDG_RUNTIME_DIR/secrets.d/age-keys.txt` (mode `0600`), sets
  `SOPS_AGE_KEY_FILE` to it, and appends `os.ReadFile(manifest.AgeKeyFile)` verbatim. Whatever
  delivers the root key must accept that it lands on a tmpfs in plaintext for the session's
  lifetime — which the map has already conceded in premise ("a Tier-1 seat sees the plaintext"), but
  it is worth stating that sops-nix makes it concrete rather than theoretical.

`sops.age.keyFile` is typed `nullOr pathNotInStore` (`sops.nix:80-86`, `:243-251`) — a custom type
whose check is `x: !lib.path.hasStorePathPrefix (/. + x)`, so **pointing it at a Nix store path is an
eval error**. The key must be a real, mutable, non-store path readable at unit-start time. That is a
hard constraint on any delivery mechanism: the file has to be *placed*, at runtime, before the user
manager starts `sops-nix.service`. sops-nix does support deriving it from an SSH key
(`sops.age.sshKeyPaths`, `:270`; `importAgeSSHKeys`, `main.go:886-913`, via `ssh-to-age`) — but the
SSH key must have **no passphrase**, because the conversion passes an empty one.

---

## What this changes about the downstream decision

- **#108 (which this ticket blocks) should be re-scoped.** A meaningful part of the north-star user's
  experience is reachable without reopening ADR-0003 — but only on a seat that keeps their home.
  Naming that split up front stops the ADR from being asked to justify itself with value it does not
  deliver.
- **Finding A's Option 1 is worth its own ticket regardless of the ADR.** It is a defect fix, not a
  feature: today's greeter produces a session with no logind registration, no `XDG_RUNTIME_DIR`, no
  systemd user manager, no keyring, and a silently non-functional sops-nix. Every one of those is
  fixed by handing the session start to greetd, and none of them requires deciding anything about
  keys.
- **The premise "delivering the root key buys the application secrets" holds — but buys less than it
  sounds like.** Nothing found here provides an alternative route to a *roaming* user's own secrets:
  the keyring is local state, sops-nix's tree is repo state that needs a key, and there is no third
  door. But the set it unlocks is the *smallest* of the three categories in
  [What is genuinely runtime-mutable](#what-is-genuinely-runtime-mutable). The ADR should say what it
  buys in those terms rather than in terms of "the user's application secrets", which overclaims.
- **There is a no-key win available now that the map has not costed.** NetworkManager profiles are
  declarable with `psk-flags = not-saved` or `agent-owned`, and NM already reads them from
  `/usr/lib/NetworkManager/system-connections/`. That gives a roaming user their networks at every
  seat with no key, no ADR, and no new contract vocabulary. It deserves comparing against the ADR on
  felt-experience-per-unit-of-mechanism before the ADR is written.
- **Roaming across desktop *stacks* is separately hostile.** Signal Desktop pins its Secret Service
  backend and refuses to start if it changes; Element does the same. A user moving between a GNOME
  seat and a KDE seat hits this regardless of what the contract does about keys — worth knowing
  before "any host × any user" is claimed for desktop apps.
- **The vocabulary split ADR-0003 demands has a natural seam here.** The credential the greeter
  already collects and *replays into PAM* is categorically different from an encryption key the
  contract would *deliver*. The first is what every login program does; the second is what 0003
  forbade. If the returning design keeps that line visible, "the contract handles no secret beyond
  the login credential" can survive Option 1 verbatim.
- **A conformance gap is now named** (Finding B): the production greeter path is unproven, and the
  bind-loop VM's `machine.succeed` root context hides both the privilege question and the session
  question. Any greeter VM added for the ADR should boot `default_session`, not `initial_session`.

---

## What could not be verified

- **Anything on a booted production greeter.** `contract.greeter.enable` with greetd's
  `default_session` does not reach `provision` (Finding B), so the inherited-`XDG_RUNTIME_DIR` claim,
  the absent user manager, and the silent sops-nix skip are all **derived from module, man-page and
  upstream source**, not observed. Confirming them needs the VM Finding B says is missing.
- **Whether greetd's `create_session` tolerates an account created moments earlier in the same boot**
  — NSS caching (`nscd`/`systemd-userdbd`) could plausibly interfere between `useradd` and
  `pam_get_user`. Not tested.
- **Which daemon wins `org.freedesktop.secrets` on a NixOS Plasma seat.** `ksecretd` claims it when
  `apiEnabled` is true (the default), and gnome-keyring claims it unconditionally when started;
  upstream has no arbitration and this was not observed on a booted system.
- **Whether a NixOS-packaged plasma-nm actually reaches QtKeychain**, and therefore whether a KDE
  seat on this fleet stores wifi PSKs agent-owned. Read from plasma-nm source, not observed.
- **Platforms other than `x86_64-linux`**, and any nixpkgs pin other than `567a49d1`.
- **sr.ht returned HTTP 418 to every automated request**, so the greetd links could not be
  machine-checked; their content was read from the nixpkgs-pinned tarball instead.
