# The contract's OWN conformance suite (ADR-0020 Q5): proves the contract's promises in
# ISOLATION — synthetic manifests bound on synthetic systems built from the contract
# umbrella + bare nixpkgs, with no host repo, no real user, and no host bindings. This is
# what gives the contract independent CI and protects it for every consumer.
#
# Because the display *backend* is a host binding (the contract only decides), this suite
# asserts the session-union DECISION (custom.gui.surface), not SDDM/Plasma. The rendering
# test (the gui-union VM) and the real-fleet coherence gate stay in the host repo.
{
  lib,
  pkgs,
  contractModule,
  greeterModule,
  homeModule,
  homeGreeterDesktopModule,
  safeSet,
  greeterGrants,
  tier1EvalConfig,
  renderNixConfig,
  featureGroups,
  privilegedGroups,
  loadIdentity,
  bindUser,
  bindUserModule,
  nixosSystem,
  system,
}:
let
  # A minimal bootable system built from ONLY the contract umbrella + bare nixpkgs.
  base =
    mods:
    nixosSystem {
      modules = [
        contractModule
        {
          nixpkgs.hostPlatform = system;
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "tmpfs";
            fsType = "tmpfs";
          };
          system.stateVersion = "25.11";
          # Stub the platform interface (ADR-0020 review F3). The contract's own CI binds
          # no real secrets backend; a no-op keeps the suite robust if a future system-side
          # secret feature reads custom.platform.secretFile during eval.
          custom.platform = {
            secretFile = _: builtins.toFile "stub-secret" "";
            secretPath = _: builtins.toFile "stub-secret" "";
          };
        }
      ]
      ++ mods;
    };
  eval = mods: (base mods).config;

  # A synthetic manifest — pure data, exactly as a real one: identity + (for gui) a
  # session preference, no grants (the host grants), no system config.
  mkUser =
    name:
    {
      gui ? true,
      session ? "wayland",
    }:
    {
      custom.users.${name} = {
        identity = {
          name = "User ${name}";
          email = "${name}@example.invalid";
          username = name;
        };
      }
      // lib.optionalAttrs gui { gui.session = session; };
    };
  grant = name: features: { custom.users.${name}.granted = features; };

  # --- grant / deny ---
  granted = eval [
    (mkUser "alice" { })
    (grant "alice" { gui.enable = true; })
  ];
  denied = eval [ (mkUser "alice" { }) ];

  # --- the gui-session union DECISION (the contract's output, not a display backend) ---
  waylandOnly = eval [
    (mkUser "alice" { session = "wayland"; })
    (grant "alice" { gui.enable = true; })
  ];
  x11Only = eval [
    (mkUser "bob" { session = "x11"; })
    (grant "bob" { gui.enable = true; })
  ];
  bothSessions = eval [
    (mkUser "alice" { session = "wayland"; })
    (mkUser "bob" { session = "x11"; })
    (grant "alice" { gui.enable = true; })
    (grant "bob" { gui.enable = true; })
  ];

  # --- the privileged-group clamp ---
  clampNoGrant = eval [
    (mkUser "alice" { })
    {
      custom.users.alice.identity.extraGroups = [
        "docker"
        "audio"
      ];
    }
  ];
  clampWithGrant = eval [
    (mkUser "alice" { })
    (grant "alice" { workstation.enable = true; })
    { custom.users.alice.identity.extraGroups = [ "docker" ]; }
  ];
  groupsOf = c: c.users.users.alice.extraGroups;

  # --- the exposed-host ban (signing is the secret-bearing feature) ---
  failing = c: builtins.filter (a: !a.assertion) c.assertions;
  exposedSecret = eval [
    (mkUser "alice" { })
    (grant "alice" { signing.enable = true; })
    {
      custom.host.exposed = true;
      networking.hostName = "agent";
    }
  ];
  normalSecret = eval [
    (mkUser "alice" { })
    (grant "alice" { signing.enable = true; })
    { networking.hostName = "box"; }
  ];

  # --- the identity.json loader (ADR-0023, issue #5): lossless over identity.nix ---
  # A fixture identity.json written at eval time, carrying the optional fields ADR-0023's
  # first 5-field schema dropped (trustedKeys, extraGroups) — the realization reads both,
  # so the loader must carry both.
  identityFixture = builtins.toFile "identity.json" (
    builtins.toJSON {
      name = "Dana Example";
      email = "dana@example.invalid";
      username = "dana";
      sshKey = "ssh-ed25519 AAAAprimary";
      trustedKeys = [ "ssh-ed25519 AAAAtrusted" ];
      extraGroups = [
        "audio"
        "docker"
      ]; # docker is privileged ⇒ must be clamped even via the loader
    }
  );
  loadedIdentity = loadIdentity identityFixture;
  loadedHost = eval [ { custom.users.dana.identity = loadedIdentity; } ];
  danaKeys = loadedHost.users.users.dana.openssh.authorizedKeys.keys;
  danaGroups = loadedHost.users.users.dana.extraGroups;

  # --- the contract.requests namespace (ADR-0018/0023, issue #5) ---
  # The home eval-side: a user's home module populates contract.requests; evalModules with
  # only the home umbrella proves the namespace's shape + enforcement with no home-manager.
  evalHome = mods: (lib.evalModules { modules = [ homeModule ] ++ mods; }).config;
  guiRequest = evalHome [ { contract.requests.gui.session = "x11"; } ];
  # An unknown FEATURE key is accepted (freeformType) and ignored — build still happens.
  unknownRequest = evalHome [ { contract.requests.bogusFeature.whatever = 42; } ];
  # A malformed KNOWN request (bad enum) must fail to evaluate (the typo-net).
  malformedRequest = builtins.tryEval (
    (evalHome [ { contract.requests.gui.session = "macos"; } ]).contract.requests.gui.session
  );

  # --- the desktop-choice home helper (ADR-0029): auto-surface ~/.contract-desktop ---
  # The helper sets `home.file`, a home-manager option the tracer-pure umbrella does not declare, so
  # — exactly as `hmStub` stands in for `home-manager.users` — a tiny stub declares `home.file` here
  # so the helper's logic is provable with no home-manager: a requested desktop materialises the
  # dotfile with that name; no request leaves it absent (⇒ the greeter falls back to the seat default).
  homeFileStub =
    { lib, ... }:
    {
      options.home.file = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submodule { options.text = lib.mkOption { type = lib.types.str; }; }
        );
      };
    };
  surfaceDesktop =
    mods:
    (lib.evalModules {
      modules = [
        homeModule
        homeFileStub
        homeGreeterDesktopModule
      ]
      ++ mods;
    }).config;
  desktopChosen = surfaceDesktop [ { contract.requests.gui.desktop = "plasma"; } ];
  desktopUnset = surfaceDesktop [ ];

  # --- the headless bindUser tracer (ADR-0023/0024, issue #5) ---
  # The first tracer bullet (ADR-0022): bind the example user against the contract with no
  # UI and no home-manager — eval the home → read identity.json → safe-set grant → the
  # system fragment that realizes the account and bridges the granted request.
  exampleHome = import ../examples/user/home.nix;
  exampleIdentity = loadIdentity ../examples/user/identity.json;
  exampleHostFacts = {
    exposed = false;
    platform = system;
    granted = { };
  };
  # Runtime path: the canonical greeter grant — default-open over the safe set (greeterGrants).
  boundRuntime = bindUser {
    userModule = exampleHome;
    identity = exampleIdentity;
    grants = greeterGrants;
    hostFacts = exampleHostFacts;
  };
  # No grants: the same gui.session request must be inert (never bridged).
  boundNone = bindUser {
    userModule = exampleHome;
    identity = exampleIdentity;
    grants = { };
    hostFacts = exampleHostFacts;
  };
  # Realize bindUser's system fragment on a synthetic host ⇒ exercises realization + union.
  boundHost = eval [ boundRuntime.system ];

  # --- the REAL bind: bindUserModule (ADR-0024, issue #8) ---
  # The mechanism the host actually imports: the home is evaluated ONCE by the host's
  # home-manager and the request→feature bridge is a config reference, so a REAL home that
  # also sets home-manager options binds (the tracer's bare evalModules would throw on them).
  #
  # The contract can't depend on home-manager (ADR-0020), so this suite supplies a package-free
  # STAND-IN for the `home-manager.users` option the bind module references: an attrsOf a
  # freeform submodule. That is exactly the part of home-manager's contract the mechanism needs
  # — it declares the option path so the config reference resolves, and the freeformType makes a
  # home that sets non-contract options (programs.git) evaluate without throwing, the way real
  # home-manager does. The contract home umbrella itself is NOT imported here: the bind module
  # imports it via the per-user `imports`, the same as the real flow. (Real home-manager
  # RENDERING — that programs.git actually materializes a dotfile — is the host's integration
  # test, the same boundary as the gui-union VM vs the gui DECISION proven here.)
  hmStub =
    { lib, ... }:
    {
      options.home-manager.users = lib.mkOption {
        default = { };
        type = lib.types.attrsOf (
          lib.types.submoduleWith {
            modules = [ { freeformType = lib.types.attrsOf lib.types.anything; } ];
          }
        );
      };
    };
  # A REAL-ish home: it sets a non-contract home-manager option (programs.git, reading the
  # injected identity) AND emits a contract request. The tracer would throw on programs.git;
  # the real bind must not. (Kept inline, NOT in examples/user/home.nix, which stays
  # contract-pure so the tracer can still harvest it — ADR-0024 / issue #5.)
  realHome =
    { config, ... }:
    {
      programs.git.userName = config.identity.name;
      contract.requests.gui.session = "wayland";
    };
  realBound =
    grants:
    eval [
      hmStub
      (bindUserModule {
        userModule = realHome;
        identity = exampleIdentity; # username "example", name "Example User"
        inherit grants;
        hostFacts = exampleHostFacts;
      })
    ];
  realBoundRuntime = realBound greeterGrants;
  realBoundNone = realBound { };

  # --- the reference greeter module (ADR-0024, issue #2, slices 2+3) ---
  # The opt-in greetd + eval-free-bind + provision module. Two eval-level claims, mirroring the
  # platform-interface litmus (ADR-0024): the module present-but-UNBOUND must not turn anything
  # on, and ENABLED it must wire greetd to the contract bind command with the grant FIXED to the
  # safe set (it cannot be widened to an operator choice). The home BUILD is a host binding
  # (homeBuilder, null by default) — building a real home needs home-manager, which the contract
  # does not depend on, so that one step stays host-side exactly like the display backend.
  greeterUnbound = eval [ greeterModule ];
  greeterBound = eval [
    greeterModule
    {
      custom.greeter.enable = true;
      custom.greeter.homeBuilder = "/run/current-system/sw/bin/true";
    }
  ];

  # The auth-flow EXECUTION test (ADR-0024 condition 1, the CANONICAL eval-free auth): pull the
  # actual shipped `contract-greeter-auth` script out of the enabled greeter's systemPackages and
  # run it against the example user repo's identity.json. It must accept the right password and
  # reject a wrong one / a mismatched username — having read only data (`jq` + libc crypt), never
  # the user's Nix. Tier 2 isolates the password check (no signature); the Tier-1 block then
  # exercises the signature branch with a real SSH key (good signature accepts, untrusted-key and
  # absent signatures reject). The cleartext for the example's hashedPassword is
  # "correct-horse-battery-staple".
  authScript =
    lib.findFirst (p: lib.hasInfix "contract-greeter-auth" (p.name or ""))
      (throw "conformance: contract-greeter-auth not found in the greeter's systemPackages")
      greeterBound.environment.systemPackages;
  exampleSrc = ../examples/user;
  authFlowTest =
    pkgs.runCommand "contract-greeter-auth-flow"
      {
        nativeBuildInputs = [
          authScript
          pkgs.openssh
        ];
      }
      ''
        export HOME=$PWD
        src=${exampleSrc}

        echo "# right password ⇒ accepts"
        printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth "$src" example tier2 /dev/null

        echo "# wrong password ⇒ rejects"
        if printf '%s\n' 'wrong-password' \
          | contract-greeter-auth "$src" example tier2 /dev/null 2>/dev/null; then
          echo "FAIL: a wrong password was accepted" >&2; exit 1
        fi

        echo "# username mismatch ⇒ rejects (no impersonation)"
        if printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth "$src" someone-else tier2 /dev/null 2>/dev/null; then
          echo "FAIL: a mismatched username was accepted" >&2; exit 1
        fi

        # --- Tier 1: the repo must be SIGNED by a host-trusted key (ADR-0022) ---
        # Build a signed source: the example identity.json + an SSH signature over the tree
        # manifest (exactly what the auth script recomputes and verifies), plus the allowed-signers
        # file a host would derive from custom.greeter.trustedSigners.
        ssh-keygen -q -t ed25519 -N "" -C trusted -f trusted
        ssh-keygen -q -t ed25519 -N "" -C attacker -f attacker
        mkdir signed
        cp "$src/identity.json" signed/identity.json
        manifest=$(cd signed && find . -type f ! -name contract.sig -print0 | sort -z | xargs -0 sha256sum)
        printf '%s' "$manifest" > manifest.txt
        ssh-keygen -Y sign -f trusted -n contract manifest.txt
        cp manifest.txt.sig signed/contract.sig
        printf '* %s\n' "$(cat trusted.pub)" > trusted-signers
        printf '* %s\n' "$(cat attacker.pub)" > attacker-signers

        echo "# tier1: a host-trusted signature over the repo ⇒ accepts"
        printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth signed example tier1 trusted-signers

        echo "# tier1: a signature by an UNTRUSTED key ⇒ rejects"
        if printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth signed example tier1 attacker-signers 2>/dev/null; then
          echo "FAIL: a signature by an untrusted key was accepted" >&2; exit 1
        fi

        echo "# tier1: no signature at all ⇒ rejects"
        if printf '%s\n' 'correct-horse-battery-staple' \
          | contract-greeter-auth "$src" example tier1 trusted-signers 2>/dev/null; then
          echo "FAIL: an unsigned repo was accepted at tier1" >&2; exit 1
        fi

        echo "eval-free auth flow OK" ; touch $out
      '';

  # The restricted-eval EXECUTION test (ADR-0030): prove the contract's PINNED Tier-1 posture, when
  # rendered to NIX_CONFIG exactly as the greeter hands it to the homeBuilder, actually RESTRICTS a
  # real Nix eval — not just that the attrset spells the right words. We run the very renderer the
  # greeter uses (renderNixConfig tier1EvalConfig) into NIX_CONFIG, then evaluate a hostile
  # expression that reads a host file. Under the posture restrict-eval=true MUST block it; without
  # the posture the same eval succeeds (the control), proving the posture is what restricts.
  tier1NixConfigFile = builtins.toFile "tier1-nix.conf" (renderNixConfig tier1EvalConfig);
  restrictedEvalTest =
    pkgs.runCommand "contract-tier1-restricted-eval"
      {
        nativeBuildInputs = [ pkgs.nix ];
      }
      ''
        export HOME=$PWD NIX_STATE_DIR=$PWD/nix/var NIX_STORE_DIR=/nix/store

        # A host file OUTSIDE the store the hostile expression tries to read by absolute path.
        secret=$PWD/host-secret
        echo "a host file no user repo should reach" > "$secret"
        expr="builtins.readFile \"$secret\""

        echo "# control: a hostile readFile evaluates WITHOUT the posture"
        nix-instantiate --eval --expr "$expr" >/dev/null \
          || { echo "FAIL: the control eval did not even run" >&2; exit 1; }

        echo "# the contract's pinned posture (via NIX_CONFIG) BLOCKS the same hostile readFile"
        export NIX_CONFIG=$(cat ${tier1NixConfigFile})
        if nix-instantiate --eval --expr "$expr" >/dev/null 2>err; then
          echo "FAIL: restrict-eval did NOT block a host-file read under the pinned posture" >&2
          exit 1
        fi
        grep -q "access to absolute path" err || grep -qi "restricted" err \
          || { echo "FAIL: blocked, but not by the restricted-eval policy:" >&2; cat err >&2; exit 1; }

        echo "tier1 restricted-eval posture OK (restrict-eval enforced via NIX_CONFIG)"
        touch $out
      '';

  # --- the matrix: synthetic users × host archetypes ---
  users = {
    alice = mkUser "alice" { session = "wayland"; };
    bob = mkUser "bob" { session = "x11"; };
    carol = mkUser "carol" { gui = false; };
  };
  userNames = [
    "alice"
    "bob"
    "carol"
  ];
  allUsers = lib.attrValues users;
  mkArchetype =
    { exposed, grantsFor }:
    base (
      [
        { custom.users = lib.mkMerge (map (u: u.custom.users) allUsers); }
        {
          custom.host.exposed = exposed;
          networking.hostName = "arch";
        }
      ]
      ++ map (n: grant n (grantsFor n)) userNames
    );
  workstationArch = mkArchetype {
    exposed = false;
    grantsFor =
      n:
      # gui users carry a gui.session (mkUser sets it only when gui); cli users don't.
      if users.${n}.custom.users.${n} ? gui then
        {
          gui.enable = true;
          workstation.enable = true;
        }
      else
        { workstation.enable = true; };
  };
  agentArch = mkArchetype {
    exposed = true;
    grantsFor = _: { workstation.enable = true; };
  };
  headlessArch = mkArchetype {
    exposed = false;
    grantsFor = _: { };
  };
  accountsRealized = sys: lib.all (n: sys.config.users.users.${n}.isNormalUser or false) userNames;
  archetypes = [
    workstationArch
    agentArch
    headlessArch
  ];

  assertions = [
    {
      # The gui grant's contract effect on the account: it confers the non-privileged
      # input groups (the uinput *device* is a host binding, tested in the host repo).
      name = "grant: gui confers its input groups (uinput) to the account";
      ok = lib.elem "uinput" (groupsOf granted);
    }
    {
      name = "deny: no grant leaves the gui input groups off";
      ok = !(lib.elem "uinput" (groupsOf denied));
    }
    {
      name = "grant: the gui surface decision is enabled";
      ok = granted.custom.gui.surface.enabled;
    }
    {
      name = "deny: the gui surface decision is off";
      ok = !denied.custom.gui.surface.enabled;
    }
    {
      name = "union: a wayland user ⇒ surface offers wayland, not x11";
      ok = waylandOnly.custom.gui.surface.wayland && !waylandOnly.custom.gui.surface.x11;
    }
    {
      name = "union: an x11 user ⇒ surface offers x11, not wayland";
      ok = x11Only.custom.gui.surface.x11 && !x11Only.custom.gui.surface.wayland;
    }
    {
      name = "union: wayland + x11 users ⇒ surface offers both";
      ok = bothSessions.custom.gui.surface.wayland && bothSessions.custom.gui.surface.x11;
    }
    {
      name = "clamp: a privileged group in identity is dropped without a grant";
      ok = !(lib.elem "docker" (groupsOf clampNoGrant));
    }
    {
      name = "clamp: a non-privileged declared group passes through";
      ok = lib.elem "audio" (groupsOf clampNoGrant);
    }
    {
      name = "grant: the workstation grant confers the privileged group";
      ok = lib.elem "docker" (groupsOf clampWithGrant);
    }
    {
      name = "exposed host granting a secret-bearing feature (signing) fails an assertion";
      ok = lib.any (a: lib.hasInfix "signing" a.message) (failing exposedSecret);
    }
    {
      name = "non-exposed host granting the same feature raises no exposed-host failure";
      ok = !(lib.any (a: lib.hasInfix "exposed host" a.message) (failing normalSecret));
    }
    {
      name = "safe set: gui is runtime-eligible";
      ok = lib.elem "gui" safeSet;
    }
    {
      name = "safe set: privileged + secret-bearing features are excluded";
      ok =
        !(lib.elem "workstation" safeSet)
        && !(lib.elem "virtualization" safeSet)
        && !(lib.elem "signing" safeSet);
    }
    {
      name = "gui confers no privileged group";
      ok = !(lib.any (g: lib.elem g privilegedGroups) featureGroups.gui);
    }
    {
      name = "virtualization confers privileged groups (only via its grant)";
      ok = lib.elem "libvirtd" featureGroups.virtualization;
    }
    {
      name = "identity.json: loadIdentity realizes the account (required fields carried)";
      ok =
        loadedHost.users.users.dana.isNormalUser
        && loadedHost.users.users.dana.description == "Dana Example";
    }
    {
      name = "identity.json: sshKey + trustedKeys both reach authorizedKeys (lossless)";
      ok = lib.elem "ssh-ed25519 AAAAprimary" danaKeys && lib.elem "ssh-ed25519 AAAAtrusted" danaKeys;
    }
    {
      name = "identity.json: a non-privileged extraGroup passes, a privileged one is clamped";
      ok = lib.elem "audio" danaGroups && !(lib.elem "docker" danaGroups);
    }
    {
      name = "requests: a known request (gui.session) is readable on the home eval";
      ok = guiRequest.contract.requests.gui.session == "x11";
    }
    {
      name = "requests: an unknown feature key is accepted and ignored (build still happens)";
      ok = unknownRequest.contract.requests.bogusFeature.whatever == 42;
    }
    {
      name = "requests: a malformed known request (bad gui.session enum) errors";
      ok = !malformedRequest.success;
    }
    {
      # ADR-0029 helper: a requested desktop is auto-surfaced to ~/.contract-desktop verbatim, so the
      # greeter's launcher (which runs before the home Nix) reads the user's choice with no manual step.
      name = "desktop helper: contract.requests.gui.desktop materialises ~/.contract-desktop";
      ok = desktopChosen.home.file.".contract-desktop".text == "plasma";
    }
    {
      # No desktop requested ⇒ no dotfile, so the greeter degrades to the seat default (ADR-0029).
      name = "desktop helper: no desktop request leaves ~/.contract-desktop absent (seat default)";
      ok = !(desktopUnset.home.file ? ".contract-desktop");
    }
    {
      name = "bindUser: the home evaluates and its gui.session request is harvested";
      ok = (boundRuntime.home ? config) && boundRuntime.requests.gui.session == "x11";
    }
    {
      name = "bindUser: the home HOLDS the injected identity (single loader, ADR-0025)";
      ok = boundRuntime.home.config.identity.name == "Example User";
    }
    {
      name = "bindUser: the account materializes from identity.json";
      ok =
        boundHost.users.users.example.isNormalUser
        && boundHost.users.users.example.description == "Example User";
    }
    {
      name = "bindUser: a safe-set grant bridges the gui request, feeding the union (x11)";
      ok = boundHost.custom.gui.surface.enabled && boundHost.custom.gui.surface.x11;
    }
    {
      name = "bindUser: an ungranted request is inert (no system feature config bridged)";
      ok = !(boundNone.system.custom.users.example ? gui);
    }
    {
      # issue #8: a REAL home (programs.git, a non-contract option) binds without throwing —
      # the harvest happens inside home-manager, not the tracer's bare evalModules.
      name = "bindUserModule: a real home-manager home (programs.git) binds and evaluates";
      ok =
        realBoundRuntime.home-manager.users.example.programs.git.userName == "Example User"
        && realBoundRuntime.home-manager.users.example.contract.requests.gui.session == "wayland";
    }
    {
      name = "bindUserModule: the account materializes from identity.json";
      ok =
        realBoundRuntime.users.users.example.isNormalUser
        && realBoundRuntime.users.users.example.description == "Example User";
    }
    {
      # The bridge is a CONFIG REFERENCE into the single home eval — the granted request feeds
      # the union without a second harvest (ADR-0018 data-flow inversion).
      name = "bindUserModule: a granted request bridges by config reference, feeding the union (wayland)";
      ok = realBoundRuntime.custom.gui.surface.enabled && realBoundRuntime.custom.gui.surface.wayland;
    }
    {
      # Post-eval `custom.users.<u>.gui` always exists (it is a declared option), so inertness
      # is proven by the observable effect: ungranted ⇒ the wayland request feeds NO surface.
      name = "bindUserModule: an ungranted request is inert (the union offers no surface)";
      ok = !realBoundNone.custom.gui.surface.enabled;
    }
    {
      # The greeter grant (ADR-0022/0024): default-open over the safe set — it enables exactly
      # the runtime-eligible features, no operator choice, no more.
      name = "greeterGrants: enables exactly the safe set (default-open, nothing beyond it)";
      ok =
        (lib.sort (a: b: a < b) (lib.attrNames greeterGrants) == lib.sort (a: b: a < b) safeSet)
        && lib.all (n: greeterGrants.${n}.enable) (lib.attrNames greeterGrants);
    }
    {
      # ADR-0024 conformance condition (3): a greeter grants AT MOST the safe set, so a
      # runtime-bound user can never receive a privileged-group or secret-bearing feature —
      # escalation is impossible by construction, not by a deny rule.
      name = "greeterGrants: grants no privileged-group or secret-bearing feature (no escalation)";
      ok =
        !(lib.elem "workstation" (lib.attrNames greeterGrants))
        && !(lib.elem "virtualization" (lib.attrNames greeterGrants))
        && !(lib.elem "signing" (lib.attrNames greeterGrants));
    }
    {
      # ADR-0024 litmus (mirrors the platform interface): the greeter ships in the eval but a
      # host that does not enable it gets nothing — greetd stays off, no seat is bound.
      name = "greeter: present-but-unbound turns nothing on (greetd disabled)";
      ok = !greeterUnbound.services.greetd.enable;
    }
    {
      name = "greeter: enabling it wires greetd to the contract bind command";
      ok =
        greeterBound.services.greetd.enable
        && lib.hasInfix "contract-greeter-bind" greeterBound.services.greetd.settings.default_session.command;
    }
    {
      # ADR-0024 condition 3: the runtime grant is FIXED to the safe set — not an operator choice,
      # impossible to widen here. So a greeter login can never receive a privileged/secret feature.
      name = "greeter: the runtime grant is fixed to greeterGrants (the safe set), unwidenable";
      ok =
        greeterBound.custom.greeter.grants == greeterGrants
        && !(lib.elem "workstation" (lib.attrNames greeterBound.custom.greeter.grants));
    }
    {
      # The home BUILD is the host's binding (ADR-0024 "the host supplies only bindings") —
      # null by default because it needs home-manager, which the contract does not depend on.
      name = "greeter: the home builder is an unbound host binding (null by default)";
      ok = greeterUnbound.custom.greeter.homeBuilder == null;
    }
    {
      # ADR-0030: the contract PINS the Tier-1 eval posture. accept-flake-config=false is the
      # un-widenable linchpin (ADR-0027 applied to eval: a repo cannot self-certify its eval by
      # declaring its own nixConfig); the rest are restrict-eval, no IFD, and a sandboxed build.
      name = "tier1 eval: the posture forbids the repo widening its own eval (accept-flake-config=false)";
      ok = tier1EvalConfig.accept-flake-config == false;
    }
    {
      name = "tier1 eval: the posture restricts eval, bans IFD, and sandboxes the build";
      ok =
        tier1EvalConfig.restrict-eval == true
        && tier1EvalConfig.allow-import-from-derivation == false
        && tier1EvalConfig.sandbox == true;
    }
    {
      # The renderer the greeter uses produces a valid nix.conf body (newline-separated key = value)
      # carrying the un-widenable linchpin — this is the exact string handed to homeBuilder as NIX_CONFIG.
      name = "tier1 eval: the rendered NIX_CONFIG carries the posture verbatim";
      ok =
        let
          rendered = renderNixConfig tier1EvalConfig;
        in
        lib.hasInfix "accept-flake-config = false" rendered && lib.hasInfix "restrict-eval = true" rendered;
    }
    {
      # The greeter EXPOSES the posture it will apply (read-only introspection, like `grants`) — fixed
      # to the contract's tier1EvalConfig, so an operator can audit the eval floor a login builds under.
      name = "greeter: it exposes the pinned tier1 eval posture, unwidenable (== tier1EvalConfig)";
      ok = greeterBound.custom.greeter.tier1EvalConfig == tier1EvalConfig;
    }
    {
      name = "matrix: every user realizes on every archetype, no failing assertion";
      ok = lib.all (sys: (accountsRealized sys) && (failing sys.config == [ ])) archetypes;
    }
    {
      name = "matrix: the workstation archetype offers both sessions (alice wayland + bob x11)";
      ok =
        workstationArch.config.custom.gui.surface.wayland && workstationArch.config.custom.gui.surface.x11;
    }
    {
      name = "matrix: the headless archetype needs no display surface";
      ok = !headlessArch.config.custom.gui.surface.enabled;
    }
    {
      name = "matrix: the exposed agent grants no gui yet realizes all users";
      ok = (!agentArch.config.custom.gui.surface.enabled) && (accountsRealized agentArch);
    }
  ];
  failures = builtins.filter (a: !a.ok) assertions;
  report = lib.concatMapStringsSep "\n" (
    a: "  ${if a.ok then "ok  " else "FAIL"}  ${a.name}"
  ) assertions;
in
pkgs.runCommand "contract-conformance"
  {
    greeterAuthFlow = authFlowTest;
    tier1RestrictedEval = restrictedEvalTest;
  }
  ''
    cat <<'EOF'
    contract conformance — synthetic users × the contract umbrella (no host repo):
    ${report}

    greeter eval-free auth flow:     ${authFlowTest} (built ⇒ ok)
    tier1 restricted-eval posture:   ${restrictedEvalTest} (built ⇒ ok)
    EOF
    ${lib.optionalString (failures != [ ]) ''
      echo "contract conformance FAILED (see above)" >&2
      exit 1
    ''}
    touch $out
  ''
