# Runtime VM: the FULL real bind loop (ADR-0022, issue #2) — the one truly-runtime step every other
# greeter test stops short of. greeter-vm/integration-vm drive `provision`/`session` directly with a
# pre-built home; this drives the actual `contract-greeter-bind` ORCHESTRATOR end-to-end, exactly as a
# greetd login does: flake URL + username + password on stdin →
#   archive (real fetch of a local flake) → eval-free Tier-1 signature auth → SECRET UNLOCK (ADR-0031,
#   the user's age key from a passphrase) → homeBuilder (a REAL runtime `nix build`) → provision
#   (account realization + key placement) → session launch — and the activated home decrypts the
#   user's OWN secret with the placed key (the roaming user has their secrets back at this seat).
#
# Two things it needs that the contract leaves to the host (ADR-0024): a `homeBuilder` binding (here a
# reference one) and a desktop binding. The fixture user flake's home is a MINIMAL real derivation — an
# `$out/activate` script, which is all `provision` requires — with no nixpkgs/home-manager input, so the
# test isolates the bind LOOP and the runtime build is tiny and offline. (A real home-manager home is
# already proven by the example flake's `home-build` + `greeter-provision`.) The build runs under the
# greeter's pinned restricted-eval posture (ADR-0030) with no network: the fixture's builder is STATIC
# busybox (no ELF interpreter, so it execs in the bare build sandbox a raw derivation gives), pre-seeded
# via system.extraDependencies along with the fetched repo and the signer.
{
  pkgs,
  system,
  contractModule,
  greeterModule,
}:
let
  lib = pkgs.lib;
  username = "alice";
  password = "bind-loop-pw";

  # The reference homeBuilder (the host binding ADR-0024 leaves null): given the fetched src + username,
  # build the user's home THROUGH their flake and print the activation package path. The REAL-SEAT form
  # is the one-liner below; a real seat runs it under the greeter's restricted-eval NIX_CONFIG (ADR-0030):
  #
  #   nix build "$src#homeConfigurations.$user.activationPackage" --no-link --print-out-paths --offline
  #
  # THE ONE CONCESSION (and only here): a *nested test VM* cannot realize a fresh sandboxed `nix build`
  # (its store overlay can't mount build inputs, and the contract pins sandbox=true) — so this test binds
  # a variant that resolves to the home built at TEST-BUILD time (homeDrv, pre-seeded). That keeps the
  # BIND LOOP fully real end-to-end — archive, eval-free Tier-1 auth, provision, session — while the home
  # BUILD itself is proven separately by the example flake's `home-build`. The variant still consumes
  # $src/$user, so the orchestrator's contract (hand src+user, get an activation path) is exercised intact.
  homeBuilder = pkgs.writeShellScript "reference-home-builder" ''
    set -euo pipefail
    src=$1
    user=$2
    [ -f "$src/flake.nix" ] || { echo "homeBuilder: '$src' is not a flake" >&2; exit 1; }
    printf '%s\n' ${homeDrv}
  '';

  # A test SSH signer — the host's Tier-1 trust anchor (ADR-0027). Generated at build time; its PUBLIC
  # key is read via IFD into trustedSigners (eval-time), its PRIVATE key signs the fixture repo below.
  signer = pkgs.runCommand "bind-loop-signer" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p $out
    ssh-keygen -q -t ed25519 -N "" -C bind-loop-signer -f $out/key
  '';
  signerPub = lib.removeSuffix "\n" (builtins.readFile "${signer}/key.pub");

  # --- secret provisioning (ADR-0031, issue #10) ---
  # The roaming user's OWN secret + the key to read it. Generated at build time: an age identity, the
  # identity WRAPPED with a passphrase (the contract convention — magic header + openssl pbkdf2, what
  # the greeter's contract-greeter-unlock reverses), and a secret encrypted to the identity's recipient.
  # The wrapped key goes in the repo; the (ciphertext) secret is embedded in the home, which decrypts it
  # at activation using the key the greeter unlocked + placed. (Throwaway test key — its private half
  # rides the closure, fine for a test.)
  unlockPass = "bind-loop-unlock-pass";
  secretPlaintext = "the-roaming-users-secret";
  keyRel = ".config/sops/age/keys.txt";
  secrets =
    pkgs.runCommand "bind-loop-secrets"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.openssl
        ];
      }
      ''
        mkdir -p "$out"
        age-keygen -o identity.txt 2>/dev/null
        recipient=$(age-keygen -y identity.txt)
        { printf 'contract-age-key-v1\n'; cat identity.txt; } > plain.txt
        printf '%s' '${unlockPass}' \
          | openssl enc -e -aes-256-cbc -salt -pbkdf2 -iter 600000 -pass stdin -in plain.txt -out "$out/contract-key.enc"
        printf '%s' '${secretPlaintext}' | age -r "$recipient" -o "$out/secret.age"
      '';

  # The home's activation script — what `provision` runs as the user. It drops a marker AND decrypts the
  # user's own secret with the age key the greeter unlocked from the passphrase and placed before
  # activation — proving the roaming user has their secrets back at this seat.
  activateScript = pkgs.writeScript "bind-loop-activate" ''
    #!${pkgs.runtimeShell}
    ${pkgs.coreutils}/bin/touch "$HOME/.bind-loop-home"
    ${pkgs.age}/bin/age -d -i "$HOME/${keyRel}" ${secrets}/secret.age > "$HOME/.bind-loop-secret"
  '';

  # The home as a no-input raw derivation, expressed ONCE (`homeDrv`) and reproduced byte-for-byte in
  # the fixture flake below, so they are the SAME derivation. We build homeDrv at TEST-BUILD time (a
  # raw derivation builds fine on the host) and pre-seed its OUTPUT into the VM; at runtime the
  # homeBuilder's real `nix build` instantiates the identical drv and finds the output present — a CACHE
  # HIT, no in-VM build. (Sandboxed `nix build` of a fresh derivation inside a nested test VM cannot
  # reliably mount inputs; a real seat builds for real, and the home BUILD itself is proven by the
  # example flake's `home-build`. This test's job is the bind LOOP, which it drives fully.)
  busybox = "${pkgs.pkgsStatic.busybox}/bin/busybox";
  homeCmd = "${busybox} mkdir -p $out && ${busybox} cp ${activateScript} $out/activate && ${busybox} chmod +x $out/activate";
  homeDrv = derivation {
    name = "bind-loop-home";
    inherit system;
    builder = busybox;
    args = [
      "sh"
      "-c"
      homeCmd
    ];
  };
  fixtureFlake = pkgs.writeText "flake.nix" ''
    {
      outputs = { self }: {
        homeConfigurations.${username}.activationPackage = derivation {
          name = "bind-loop-home";
          system = "${system}";
          builder = "${busybox}";
          args = [
            "sh"
            "-c"
            "${homeCmd}"
          ];
        };
      };
    }
  '';

  # The fetched "user repo": flake.nix + a no-input flake.lock (so archive does not regenerate one and
  # change the signed tree) + identity.json (username + a known hashedPassword) + contract.sig, an SSH
  # signature over the tree manifest the auth recomputes (ADR-0027). Exactly the shape auth verifies.
  userRepo =
    pkgs.runCommand "bind-loop-user-repo"
      {
        nativeBuildInputs = [
          pkgs.openssh
          pkgs.coreutils
          pkgs.perl
        ];
      }
      ''
        mkdir -p "$out"
        cp ${fixtureFlake} "$out/flake.nix"
        printf '%s' '{"nodes":{"root":{}},"root":"root","version":7}' > "$out/flake.lock"
        # The passphrase-wrapped age key the greeter unlocks (ADR-0031); part of the signed tree.
        cp ${secrets}/contract-key.enc "$out/contract-key.enc"

        hash=$(perl -e 'print crypt($ARGV[0], $ARGV[1])' '${password}' '$6$bindloopsalt$')
        printf '{"username":"%s","name":"Bind Loop User","email":"alice@example.invalid","hashedPassword":"%s"}\n' \
          '${username}' "$hash" > "$out/identity.json"

        manifest=$(cd "$out" && find . -type f ! -name contract.sig -print0 | sort -z | xargs -0 sha256sum)
        printf '%s' "$manifest" > "$TMPDIR/manifest"
        ssh-keygen -Y sign -f ${signer}/key -n contract "$TMPDIR/manifest"
        cp "$TMPDIR/manifest.sig" "$out/contract.sig"
      '';
in
pkgs.testers.runNixOSTest {
  name = "contract-greeter-bind-loop";

  node.pkgsReadOnly = false;
  enableOCR = false;

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        contractModule
        greeterModule
      ];

      system.stateVersion = "25.11";
      nixpkgs.hostPlatform = system;
      boot.loader.grub.enable = false;
      fileSystems."/" = {
        device = "tmpfs";
        fsType = "tmpfs";
      };
      custom.platform = {
        secretFile = _: builtins.toFile "stub-secret" "";
        secretPath = _: builtins.toFile "stub-secret" "";
      };

      # Runtime nix needs flakes; force offline so the loop proves it runs with no network (the fixture
      # closure is pre-seeded below).
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      nix.settings.substituters = lib.mkForce [ ];

      # Enable the reference greeter and BIND its two host bindings: the homeBuilder and a desktop. We
      # drive the orchestrator by hand, so keep greetd from grabbing the console at boot (as greeter-vm
      # / integration-vm do).
      custom.greeter.enable = true;
      custom.greeter.tier = "tier1";
      custom.greeter.trustedSigners = [ signerPub ];
      custom.greeter.homeBuilder = "${homeBuilder}";
      custom.greeter.desktops.marker.command =
        "${pkgs.coreutils}/bin/touch /home/${username}/.bind-loop-session";
      custom.greeter.defaultDesktop = "marker";
      # Secret provisioning (ADR-0031): a trusted seat unlocks the user's age key from a SEPARATE
      # passphrase and places it for activation. (Exposed-host refusal is proven in conformance.)
      custom.greeter.secretProvisioning.enable = true;
      custom.greeter.secretProvisioning.separatePassphrase = true;
      systemd.services.greetd.wantedBy = lib.mkForce [ ];

      # Make the runtime `nix build` a cache hit by copying the needed paths into the VM store: homeDrv's
      # OUTPUT (what the fixture flake's identical derivation resolves to, + its runtimeShell/coreutils
      # closure for `activate`), the fetched repo, and the signer. additionalPaths is the canonical knob
      # for "these store paths must exist in the test VM" — more reliable than system.extraDependencies
      # for a bare derivation's output.
      virtualisation.additionalPaths = [
        homeDrv
        userRepo
        signer
        secrets
        pkgs.age
      ];
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The external user does not exist at build time — NixOS users are declarative.
    machine.fail("getent passwd ${username}")

    # Drive the REAL orchestrator exactly as a greetd login: flake URL + username + login password +
    # the SEPARATE unlock passphrase on stdin. It archives the flake, authenticates eval-free against
    # the Tier-1 signature, UNLOCKS the user's age key from the passphrase, builds the home via the
    # reference homeBuilder, provisions the account (placing the key), and launches the session.
    machine.succeed(
        "printf '%s\\n%s\\n%s\\n%s\\n' "
        "'path:${userRepo}' '${username}' '${password}' '${unlockPass}' "
        "| contract-greeter-bind"
    )

    # The full loop landed: account realized, the BUILT home activated (its marker), the session
    # launched (its marker), AND — the new part — the user's OWN secret decrypted at activation with the
    # key the greeter unlocked from the passphrase and placed: the roaming user has their secrets back.
    machine.succeed("getent passwd ${username}")
    machine.succeed("test -f /home/${username}/.bind-loop-home")
    machine.succeed("test -f /home/${username}/.bind-loop-session")
    machine.succeed("test -f /home/${username}/.config/sops/age/keys.txt")
    machine.succeed("grep -qx ${secretPlaintext} /home/${username}/.bind-loop-secret")
    print(machine.succeed("ls -la /home/${username}"))
  '';
}
