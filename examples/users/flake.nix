{
  description = "Reference USER FLEET (ADR-0020) — the operator's own accounts grouped in ONE repo, each consumed by a host through the contract's pre-built binding (ADR-0016). Every user lives under users/, one subdir each: identity.json + home.nix and NOTHING else (no per-user check file — the coverage here is roster-generic). This flake is a GENERIC MAPPER over that directory: it hardcodes no user, states no user's offer, and contributes no module of its own, so adding a user is writing those two files. The variant set is the CONTRACT's own (`contract.variants`); the one thing stated here is the per-system BAKE MATRIX over it, which is this fleet's topology and nobody else's. Standalone inputs exist only for this repo's own CI; when a host binds a user it supplies the canonical contract + pkgs. This is the positive-space reference the synthetic conformance suite borrows real atoms from — never the reverse (see docs/adr/0022).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # A real user repo uses `github:palebluebytes/host-user-contract`; the in-repo example
    # points at the contract two levels up. nixpkgs follows so there is ONE nixpkgs.
    contract.url = "path:../..";
    contract.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    # No `self`: every home is evaluated ONCE, in `homes`/`greeterHomes` below, and the published
    # names, the binding artifacts and the checks all read THAT. Going back through
    # `self.homeConfigurations` would also force this file to spell a user's published name to
    # reach its home — the hand-listing the mapper exists to kill.
    {
      nixpkgs,
      contract,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      # The system this flake publishes its `home-manager switch` surface on. NOT a per-user fact:
      # every user bakes for every entry of `systems` below.
      system = "x86_64-linux";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # PLAIN nixpkgs — the producer contributes NO overlay and NO config. A user's own pkgs
      # (ADR-0007) is declared by its OWN home: home-manager re-imports nixpkgs inside every home
      # eval and CONCATENATES the home's `nixpkgs.overlays` onto the ones the producer passed, so
      # the duo pair's `shared/overlay.nix` merges rather than replaces (spelled out there). Held
      # per system and looked up, so nixpkgs is instantiated once per system rather than once per
      # user × variant.
      pkgsBySystem = lib.genAttrs systems (sys: nixpkgs.legacyPackages.${sys});
      pkgs = pkgsBySystem.${system};

      # ── The roster, DERIVED from the directory ───────────────────────────────────────────────
      # The reference fleet is every subdir of ./users/ holding an identity.json. Derived, never
      # listed: adding `users/<new>/{identity.json,home.nix}` needs no edit to this file — the
      # homes, the greeter homes, both arches' binding artifacts, the checks and the posture guard
      # all follow. Each user's own story lives in the header of its own `home.nix`, because it
      # travels with the user: lifting one out into a standalone repo is a directory move.
      #
      # What is FLEET-level, and so lives here rather than in any user:
      #
      #   - The two CODE-SHARING arrangements, side by side (ADR-0020 as amended by issue #36:
      #     sharing home modules and overlays is PERMITTED, not required, so the optional shape
      #     needs a live fixture or it rots). ada, ben, cleo, svc and admin share no module and no
      #     overlay — there is nothing universal to factor across them (what a home DOES with the
      #     contract's signal is application policy that varies per user), and it keeps each a clean
      #     standalone artifact; ada in particular stays evaluable headlessly, since the conformance
      #     tracer borrows her home.nix with no home-manager at all (ADR-0022). duo-a and duo-b
      #     import ONE `shared/module.nix` and ONE `shared/overlay.nix` — the mechanism an operator
      #     uses to enforce a common setup across their own accounts, keyed on
      #     `config.identity.username` so the same code yields per-user data (the
      #     `shared-code-per-user-data` check below proves exactly that). Neither arrangement reaches
      #     sideways between users' DATA; they differ only in whether the CODE is written once or
      #     per user.
      #
      #   - The PUBLIC-repo credential posture (ADR-0019): every identity.json ships a `$y$`
      #     yescrypt hash rather than `$6$` sha512crypt, because a world-readable hash must be
      #     memory-hard. The reference fleet is what consumers copy, so it models the rule instead of
      #     merely citing it, and `identity-posture` below enforces it. (The cleartexts are published
      #     on purpose — "correct-horse-battery-staple", and "password" for admin — because these are
      #     teaching fixtures: the posture is modelled for the shape a real repo must copy, not
      #     because these particular hashes guard anything.)
      #
      #   - No user's OFFER appears here (ADR-0028). Each user declares `contract.wants` in its own
      #     home and `mkContractUsers` HARVESTS it into the binding index, so a user's voice is not
      #     split between its home and the producer's flake. The negotiation is unchanged: a host
      #     declares `contract.affordances` once and each grant is derived as `affordances ∩ offer`,
      #     so ada is gui on a seat that affords gui and cli-only on a headless host.
      usersDir = ./users;
      userNames = lib.filter (
        n:
        (builtins.readDir usersDir).${n} == "directory"
        && builtins.pathExists (usersDir + "/${n}/identity.json")
      ) (lib.attrNames (builtins.readDir usersDir));
      userDirOf = n: usersDir + "/${n}";
      # ADR-0009: the contract is the one identity loader. Resolved once per user here and handed to
      # the homes and the posture check, rather than each re-reading the file. (`mkContractUsers`
      # loads its own from the `usersDir` it is given — that is the point of handing it the roster
      # and nothing else, so this file never passes an identity path.)
      identities = lib.genAttrs userNames (n: contract.lib.loadIdentity (userDirOf n + "/identity.json"));

      # ── The bake matrix: which variants, on which system ─────────────────────────────────────
      # `contract.variants` is the contract's own answer to "what could a host grant?": one entry per
      # combination of the features whose grant cannot be applied to an already-built home, each
      # carrying the grants to bake with and the label to publish under. Today that is base + gui; a
      # second such feature fans out there, with no edit here.
      #
      # That set is an UPPER BOUND, never a per-system baking obligation. WHICH of it a system bakes
      # is the consuming fleet's topology and nobody else's, so the rule below is a MODELLED one:
      # this reference fleet declares its aarch64 tier headless (the shape a real fleet has — a
      # headless arm builder beside the x86 desktop seats), and so bakes base alone there. An
      # aarch64 host that granted gui would bind base — ∅ ⊆ anything, the ADR-0002 degradation
      # posture, accepted deliberately. `examples/fleet` is x86-only and binds none of the aarch64
      # bakes; they exist to teach the matrix, and to give `variant-eval` a real cross-arch fact to
      # prove rather than a one-row one.
      #
      # Written as the features a system's seats CANNOT use, rather than a per-system list of labels,
      # so that a contract which gains an axis bakes it EVERYWHERE until this file says otherwise. A
      # label list would drop the new variant from aarch64 in silence, which is the one failure mode
      # this area keeps having: `bindContractUser` binds the maximal variant that DOES exist, so an
      # under-baked set costs a home its content with nothing objecting.
      #
      # The matrix says what a HOST could grant; what each home DOES with it is that home's own
      # business, and this roster shows both answers. Most of these homes are thin and read no
      # grant, so their `gui` bake differs from `base` only in the `granted` field frozen into the
      # manifest — which is exactly what lets one `ada-contractPackage-base` be a gui account on one
      # seat and a cli-only account on another, the account-side effects riding the bind.
      #
      # duo-a is the other answer, and the one the matrix exists FOR (issue #55): it wires
      # `custom.home.profiles.gui.enable` off `hostFacts.granted.gui.enable` and gates real home
      # content on that, so its two bakes differ in CONTENT — no bind-time grant could put a sway
      # config into an already-built base home, which is precisely what `needsOwnBuild` names. The
      # `home-affecting-grant-is-load-bearing` check below fails if the roster ever loses that.
      unusableOn = sys: lib.optional (sys == "aarch64-linux") "gui";
      variantsFor = sys: lib.filter (v: !lib.any (f: v.grants ? ${f}) (unusableOn sys)) contract.variants;

      # The matrix itself, `bakedVariants.<system>`. Everything below bakes off THIS.
      #
      # The assert pins where the upper bound must still HOLD: the x86_64 seats can use anything the
      # contract names, so their bake must be the contract's whole set. An `unusableOn` rule that
      # ever leaks into them is an under-bake, and silent for the reason just given.
      bakedVariants =
        assert lib.assertMsg (variantsFor "x86_64-linux" == contract.variants)
          "the x86_64-linux bake must equal the contract's full variant set — its seats can use every feature the contract names — but the per-system filter cuts it to [${
            lib.concatMapStringsSep ", " (v: v.label) (variantsFor "x86_64-linux")
          }] of [${
            lib.concatMapStringsSep ", " (v: v.label) contract.variants
          }]. Filtering is for systems whose seats CANNOT use a feature (this fleet models its aarch64 tier headless); x86_64 bakes the upper bound.";
        lib.genAttrs systems variantsFor;

      # ── This repo's home builder ─────────────────────────────────────────────────────────────
      # A THIN partial application of the contract's own `mkContractHome` (ADR-0029): the builder
      # owns the composition every producer used to hand-write — the home umbrella, the home
      # baseline, the user's `home.nix`, the inline identity/`home.*` module, and the `hostFacts`
      # specialArg built by `hostFactsFor` (which NARROWS `granted` to the variant axes, so a home
      # reading `granted.sudo` structurally gets false forever rather than becoming grant-sensitive
      # on a feature that rides the bind).
      #
      # That inline module is also what keeps the five self-contained users contract-pure: the
      # home-manager glue a bound path gets from the host (`home.username`, `home.homeDirectory`,
      # `home.stateVersion`) lives in the BUILDER, never in their `home.nix`, so those homes still
      # evaluate against the bare umbrella with no home-manager (ADR-0008/0022).
      #
      # What is fixed here is exactly what is this repo's own: home-manager's builder passed
      # verbatim (the ADR-0004 injection that keeps the CONTRACT package-free — it applies a
      # function it never imports), the `stateVersion` (a required argument precisely because real
      # repos differ, so the contract carries no default), and the per-system pkgs.
      #
      # `extraSpecialArgs` is deliberately NOT threaded: no user here consumes an external flake, so
      # the ADR-0020 `inputs` passthrough is a real users repo's story, not this example's. Named
      # rather than inlined so the published homes and the confinement check drive the SAME module
      # set (issue #35) — a check over a separately assembled module set would prove nothing about
      # what ships.
      mkHome =
        {
          userDir,
          identity,
          granted ? { },
          extraModules ? [ ],
          # Override to build for another system; the home layers its own overlays on whatever it gets.
          pkgs ? pkgsBySystem.${system},
        }:
        contract.lib.mkContractHome {
          inherit
            userDir
            identity
            granted
            extraModules
            pkgs
            ;
          homeManagerConfiguration = home-manager.lib.homeManagerConfiguration;
          stateVersion = "25.11";
        };

      # One user's whole baked set for one system, keyed by variant label — the system's row of the
      # matrix, so aarch64 yields `{ base }` where x86_64 yields `{ base, gui }`.
      variantHomesFor =
        args: sys:
        lib.listToAttrs (
          map (
            v:
            lib.nameValuePair v.label (
              mkHome (
                args
                // {
                  granted = v.grants;
                  pkgs = pkgsBySystem.${sys};
                }
              )
            )
          ) bakedVariants.${sys}
        );

      # The whole fleet: `homes.<system>.<user>.<label>`. Computed ONCE rather than per consumer, so
      # the published names, the binding artifacts and the checks share one evaluation of each home.
      homes = lib.genAttrs systems (
        sys:
        lib.genAttrs userNames (
          n:
          variantHomesFor {
            userDir = userDirOf n;
            identity = identities.${n};
          } sys
        )
      );

      # ── The greeter-login home, for EVERY roster member ──────────────────────────────────────
      # `<u>-greeter`: the same user through the same builder, granted the contract's safe set
      # (`greeterGrants` — what a runtime greeter may confer with no declarative say-so from the
      # host), plus two extra modules through the builder's open seam:
      #   - the desktop-choice helper (ADR-0013), so `contract.requests.gui.desktop` surfaces to
      #     `~/.contract-desktop`, where the greeter's session launcher reads it;
      #   - a marker dotfile the fleet's integration VM observes to prove the REAL home activated at
      #     runtime rather than a stub.
      # Roster-generic on purpose: baking only the one user `examples/fleet` happens to consume is
      # the hand-listing failure mode this file exists to kill. The marker is keyed on the injected
      # identity, so it names no user either.
      greeterMarker =
        { config, ... }:
        {
          home.file.".contract-home-active".text = "greeter-activated for ${config.identity.name}";
        };
      greeterHomes = lib.genAttrs userNames (
        n:
        mkHome {
          userDir = userDirOf n;
          identity = identities.${n};
          granted = contract.greeterGrants;
          extraModules = [
            contract.homeModules.greeterDesktop
            greeterMarker
          ];
        }
      );

      # ── Turnkey producer bindings (ADR-0025/0026/0028, issue #25) ────────────────────────────
      # `mkContractUsers` maps the DERIVED roster ONCE per system into BOTH the named per-variant
      # packages (`<user>-contractPackage-<label>`) AND the pure `contractUsers.<sys>.<user>` binding
      # INDEX a host selects from with `contract.lib.bindContractUser` (deriving the grant as its
      # `contract.affordances` ∩ the user's offer, then binding the maximal covered variant). It
      # bakes through the internal package kernels, which only READ an already-evaluated home, and
      # resolves each identity from `users/<u>/identity.json` — so this call passes only the roster
      # and never a user's name, offer or identity path.
      #
      # This is the one place the matrix is RE-PAIRED: each home is looked up by `v.label` and handed
      # back alongside `v.grants`. Both sides come from the same `bakedVariants` row, so the pairing
      # is right by construction here — and since issue #56 it is also CHECKED, because right-by-
      # construction is a property of this file rather than of the shape being taught. `mkContractHome`
      # gives every home the grant-key it was baked under, so a producer that pairs `homes.….base`
      # with the `gui` grants fails the bake by name instead of publishing a base home as the gui
      # variant — which no downstream guard could have seen (they all read this `grants`, not the home).
      bindings = lib.genAttrs systems (
        sys:
        contract.lib.mkContractUsers {
          pkgs = pkgsBySystem.${sys};
          system = sys;
          inherit usersDir;
          users = lib.genAttrs userNames (n: {
            variants = map (v: {
              inherit (v) grants;
              home = homes.${sys}.${n}.${v.label};
            }) bakedVariants.${sys};
          });
        }
      );

      # The published package set per system — every user's baked variants, so aarch64's is the base
      # bakes alone. Named here because `checks` is literally this set plus the repo's own.
      packages = lib.genAttrs systems (sys: bindings.${sys}.packages.${sys});
    in
    {
      # The `home-manager switch` surface, on the default system only (other systems' homes are
      # reachable through `packages.<sys>`; switching is an x86 desktop affair here). The names are
      # THIS repo's own and owe the published packages nothing — a host binds through
      # `contractUsers`, and `mkContractUser` names its own artifacts — so the rule is local and
      # trivial: the base variant keeps the bare user name, any other variant is suffixed with its
      # label, and the greeter home is suffixed `-greeter`.
      homeConfigurations =
        lib.listToAttrs (
          lib.concatMap (
            n:
            map (
              v:
              lib.nameValuePair (
                if v.label == "base" then n else "${n}-${v.label}"
              ) homes.${system}.${n}.${v.label}
            ) bakedVariants.${system}
          ) userNames
        )
        // lib.mapAttrs' (n: home: lib.nameValuePair "${n}-greeter" home) greeterHomes;

      # The pre-built binding artifacts (ADR-0016), for every user × baked variant × system. Each is
      # content-addressed and carries `activate` + `contract-requests.json` (with the baked `granted`
      # field the ADR-0025 coupling guard asserts the host actually grants):
      #   - x86_64-linux: <user>-contractPackage-{base,gui}
      #   - aarch64-linux: <user>-contractPackage-base alone — the matrix bakes no gui there.
      inherit packages;

      # The turnkey binding INDEX (ADR-0025): `contractUsers.<sys>.<user> = { identity; offer;
      # variants = [{ granted; package }] }` — plain data (no IFD), so a host's `bindContractUser`
      # picks a variant by reading it, never by building every variant to inspect a baked manifest.
      contractUsers = lib.foldl' (acc: sys: acc // bindings.${sys}.contractUsers) { } systems;

      # ── Checks ──────────────────────────────────────────────────────────────────────────────
      # `checks = packages`, plus the contract's consumer check kit mapped over the derived roster.
      # There are no per-user checks — not "none yet": a user here ships `identity.json` + `home.nix`
      # and nothing else, and this mapper carries no hook to pick a check file up with. Everything
      # below is generic over the roster, so a new user is covered the moment its directory exists.
      #
      # The first clause is the load-bearing one: a contractPackage build-DEPENDS on its activation
      # package (`mkContractPackage` interpolates `${activationPackage}/activate` into its
      # runCommand), so building every package builds every home — the hand-written per-user
      # `home-build-*` checks this flake used to carry are subsumed by one line. The REAL home build
      # is the model a real user repo follows when it CIs its own homes; the contract's own suite
      # cannot cover it (it needs home-manager, which the contract does not depend on — ADR-0004),
      # and the greeter path end-to-end lives in `examples/fleet`, which needs a booted host.
      checks = lib.genAttrs systems (
        sys:
        packages.${sys}
        // lib.optionalAttrs (sys == system) (
          # Structural confinement, per user (check kit, issue #35). `conformance/confinement.nix`
          # proves the contract UMBRELLA declares no system channel; that says nothing about whether
          # THIS repo's imports smuggled one back in. `mkConfinementCheck` closes that half by
          # probing the real `mkHome` above: an out-of-universe option must be unexpressible
          # (throws) while a legitimate home option still evaluates (the positive control that stops
          # the check passing vacuously). Run over EVERY user, because a system channel arrives
          # through an import and each user owns its own imports — the duo-a-only economy this flake
          # used to run was a fact about these particular fixtures, not about the shape being taught.
          # These call sites are also what exercise the helper's two DEFAULTS (the
          # `activationPackage.drvPath` force and the `home.sessionVariables` positive control),
          # which the contract's own suite structurally cannot reach.
          lib.mapAttrs' (
            n: identity:
            lib.nameValuePair "home-confinement-${n}" (
              contract.lib.mkConfinementCheck {
                inherit pkgs;
                name = "home-confinement-${n}";
                buildHome =
                  extraModules:
                  mkHome {
                    userDir = userDirOf n;
                    inherit identity extraModules;
                  };
              }
            )
          ) identities
          // lib.mapAttrs' (
            n: _:
            lib.nameValuePair "variant-eval-${n}" (
              # Bake evaluability, per user (check kit, issue #49): every variant this repo bakes for
              # that user, on every system it bakes for, forces to a derivation. This is the
              # roster-generic replacement for the cross-arch eval checks a user's own checks.nix
              # would otherwise hand-write — the failing arch is always the one nothing builds by
              # default here, so an x86_64-only package added to base content throws in THIS check
              # rather than on the aarch64 seat hours later.
              #
              # It reads the shared `homes` eval, so it costs nothing the packages have not already
              # paid for natively, and the helper's own anti-vacuous assert makes a per-system filter
              # that accidentally empties a bake fail here instead of reading green. WHICH variants
              # belong in the matrix is deliberately not its business — that is the assert up at
              # `bakedVariants`, each fact stated once.
              contract.lib.mkVariantEvalCheck {
                inherit pkgs systems;
                name = "variant-eval-${n}";
                homesFor = sys: homes.${sys}.${n};
              }
            )
          ) identities
          // {
            # ADR-0019's credential posture, ENFORCED rather than merely documented (issue #35).
            # This repo is PUBLIC, so a world-readable hash must be memory-hard: every roster
            # identity ships `$y$`, and this is what keeps that true — a member added with a `$6$`
            # hash fails the flake check rather than being noticed in review, or not. The roster is
            # DERIVED, so a new user is covered the moment it exists; a hand-listed set is the
            # failure mode this check is for, since the offender is always the entry someone forgot
            # to add to the list.
            identity-posture = contract.lib.mkIdentityPostureCheck {
              inherit pkgs;
              identities = lib.attrValues identities;
              require = "yescrypt";
            };

            # …and the proof that the check above can actually FAIL. Kept here deliberately, as a
            # teaching extra a real users repo does not carry: a posture check that passes because
            # its identity list is empty, or because the derivation quietly yielded nothing, reads
            # identically to one that passes on merit — the same vacuity trap the confinement check's
            # positive control closes.
            #
            # So: take the REAL derived roster, append one synthetic `$6$` offender, and require that
            # the check rejects it. This tests the CALL SITE, not the helper (conformance already
            # covers the helper): it proves the roster derivation yields real identities and that an
            # offender among them is caught. If the derivation ever silently yielded `[ ]`, this
            # check goes red while the one above would stay green.
            identity-posture-rejects-an-offender =
              let
                # Any real roster identity will do as the base — the offender differs from it only
                # in the two fields the posture looks at — so it is taken from the derivation rather
                # than by naming a user this check has no other business knowing.
                someRealIdentity = lib.head (lib.attrValues identities);
                offender = someRealIdentity // {
                  username = "sixto";
                  hashedPassword = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
                };
                rejected =
                  !(builtins.tryEval (
                    contract.lib.mkIdentityPostureCheck {
                      inherit pkgs;
                      identities = lib.attrValues identities ++ [ offender ];
                      require = "yescrypt";
                      name = "identity-posture-offender-probe";
                    }
                  )).success;
              in
              assert lib.assertMsg rejected (
                "identity-posture-rejects-an-offender: a `$6$` identity appended to the real roster did "
                + "NOT fail `require = \"yescrypt\"`. The posture check above is therefore vacuous — it "
                + "would pass whatever the roster ships. Check that the roster derives a non-empty list "
                + "from ./users."
              );
              pkgs.runCommand "identity-posture-rejects-an-offender" { } "touch $out";

            # The ADR-0020 claim the duo pair exists to prove: SHARED CODE, PER-USER DATA. Also kept
            # deliberately as a teaching extra — it is the one check here that names users, because
            # the arrangement it proves is a property of that pair rather than of the roster. "Both
            # homes build" would not prove it: a shared module that baked duo-a's identity into
            # duo-b's home would still build. So this pins the two halves separately, on the REALIZED
            # homes:
            #
            #   shared CODE   — `shared/overlay.nix`'s marker package resolves to the SAME store path
            #                   in both closures (one derivation, not a per-user copy), and it is
            #                   really there: the check RUNS it out of each home-path, which is what
            #                   makes this an overlay proof rather than an overlay mention;
            #   per-user DATA — `shared/module.nix`, keyed on `config.identity.username`, renders two
            #                   DIFFERENT store paths, each carrying its own identity and NO trace of
            #                   the other's (name, email, or username).
            #
            # This is also why the check lives here rather than in `conformance/`: it needs both
            # home-manager and nixpkgs, and the synthetic suite's `toolkit.evalHome` has neither
            # (ADR-0004/0022). CI already runs `nix flake check` on this flake as a matrix entry.
            shared-code-per-user-data =
              let
                duoA = homes.${system}.duo-a.base;
                duoB = homes.${system}.duo-b.base;
                # Both halves are read out of the REALIZED activation package, never off the evaluated
                # config: the point is what actually lands in the user's home, not what the module said.
                cardOf = home: "${home.activationPackage}/home-files/.contract-shared-card";
                markerOf = home: "${home.activationPackage}/home-path/bin/contract-shared-marker";
              in
              pkgs.runCommand "shared-code-per-user-data" { } ''
                fail() {
                  echo "shared-code-per-user-data: $1" >&2
                  exit 1
                }

                # --- shared CODE: one overlay, one derivation, in BOTH closures ---
                markerA=$(readlink -f ${markerOf duoA})
                markerB=$(readlink -f ${markerOf duoB})
                [ -x "$markerA" ] || fail "duo-a's home-path has no runnable shared-overlay marker"
                [ -x "$markerB" ] || fail "duo-b's home-path has no runnable shared-overlay marker"
                [ "$markerA" = "$markerB" ] || fail "the shared overlay produced a DIFFERENT package per user ($markerA vs $markerB) — that is not shared code"
                "$markerA" | grep -q 'shared/overlay.nix' || fail "the marker in the closure did not come from the shared overlay"

                # --- per-user DATA: same module, two identities, two different outputs ---
                # Each home's card is a symlink into the store, so resolving it gives the derivation the
                # shared module rendered for THAT identity. Two distinct paths ⇒ genuinely keyed output.
                cardA=$(readlink -f ${cardOf duoA})
                cardB=$(readlink -f ${cardOf duoB})
                [ -f "$cardA" ] || fail "duo-a's realized home has no shared-module card"
                [ -f "$cardB" ] || fail "duo-b's realized home has no shared-module card"
                [ "$cardA" != "$cardB" ] || fail "the shared module rendered ONE output for two identities — it is not keyed on config.identity.username"

                grep -q '^username=duo-a$' "$cardA" || fail "duo-a's card is not keyed on duo-a's username"
                grep -q '^username=duo-b$' "$cardB" || fail "duo-b's card is not keyed on duo-b's username"
                grep -q 'Duo A Reference' "$cardA" || fail "duo-a's card lost duo-a's own identity"
                grep -q 'Duo B Reference' "$cardB" || fail "duo-b's card lost duo-b's own identity"

                # --- and neither carries a TRACE of the other's identity ---
                ! grep -q 'duo-b\|Duo B' "$cardA" || fail "duo-a's home leaks duo-b's identity — the shared module baked a user in"
                ! grep -q 'duo-a\|Duo A' "$cardB" || fail "duo-b's home leaks duo-a's identity — the shared module baked a user in"

                touch $out
              '';

            # The property the VARIANT system exists for, pinned so it cannot rot back into a
            # manifest-only difference (issue #55): somewhere in this roster a home-affecting grant
            # is LOAD-BEARING — a non-base bake whose realized home CONTENT differs from the base
            # bake's. `needsOwnBuild` is defined by exactly that mechanical test ("build the home
            # with the grant and without it, and see whether the two differ"), so a fleet whose
            # `gui` bake is content-identical to its `base` one bakes a variant for nothing, and
            # teaches the vocabulary it travels through (`custom.home.profiles.*`, wired off
            # `hostFacts.granted`) with the wire missing.
            #
            # Roster-generic on purpose, unlike `shared-code-per-user-data` above: WHICH user gates
            # content on a grant is that user's own story, told in its own `home.nix` (today
            # duo-a's), so this names no user. It asks the roster whether the demonstration exists
            # AT ALL, and then proves each surviving pair differs where it must:
            #
            #   the ASSERT — at least one (user, non-base bake) pair diverges from that user's base
            #                bake. This is the anti-convergence half: delete the wire, or let the
            #                gated content dry up, and NOTHING diverges — the flake then fails to
            #                evaluate with a named message instead of quietly baking twins.
            #   the BUILD  — every diverging pair really differs in what the user RECEIVES: the
            #                realized dotfiles or the realized package profile. The manifest is in
            #                neither, so a difference in the baked `granted` field cannot satisfy
            #                this half.
            #
            # Lives inside the `sys == system` clause with the rest, and needs to: the aarch64 row
            # of the matrix is headless, so it bakes base ALONE and there is no second bake there to
            # compare — the assert below would then abort rather than pass. Its subject is the
            # roster's demonstration, which needs one system to exist on, not every system.
            home-affecting-grant-is-load-bearing =
              let
                # Every (user, non-base bake) pair the matrix produces on this system. "base" is
                # this repo's own label for the grant-less bake, the same literal `homeConfigurations`
                # above names it by.
                pairs = lib.concatMap (
                  n:
                  map (v: {
                    user = n;
                    inherit (v) label;
                    base = homes.${system}.${n}.base;
                    variant = homes.${system}.${n}.${v.label};
                  }) (lib.filter (v: v.label != "base") bakedVariants.${system})
                ) userNames;
                # Divergent = the grant reached the BUILD. Compared on drvPath because that is the
                # sharpest test available: two bakes of one home differ ONLY in `hostFacts.granted`,
                # so a home that reads no grant lands on the very same derivation twice.
                divergent = lib.filter (
                  p: p.base.activationPackage.drvPath != p.variant.activationPackage.drvPath
                ) pairs;
                # The two places a grant's content can LAND in a realized home. Both are checked,
                # because either alone would fail the canonical demonstration the other way round:
                # a home gating `home.file` puts nothing in the profile, and one gating
                # `home.packages` (ADR-0025's own example — gui → emacs, ai) puts nothing in the
                # dotfiles.
                filesOf = home: "${home.activationPackage}/home-files";
                profileOf = home: "${home.activationPackage}/home-path";
              in
              assert lib.assertMsg (divergent != [ ]) (
                "home-affecting-grant-is-load-bearing: NO reference user's non-base bake differs from its "
                + "base bake — every variant this fleet bakes lands on the same activation package as the "
                + "base one, so the only thing a `gui` bake carries is the `granted` field frozen into its "
                + "manifest, and the one mechanism the variant system exists for has no worked example. "
                + "Restore the wire in a home that HAS home-manager content to gate (a contract-pure home "
                + "has none): `custom.home.profiles.gui.enable = hostFacts.granted.gui.enable or false;` "
                + "plus real content behind `lib.mkIf config.custom.home.profiles.gui.enable`."
              );
              pkgs.runCommand "home-affecting-grant-is-load-bearing" { } (
                ''
                  fail() {
                    echo "home-affecting-grant-is-load-bearing: $1" >&2
                    exit 1
                  }
                ''
                + lib.concatMapStrings (p: ''
                  # --- ${p.user}: base vs ${p.label} ---
                  differed=""

                  # The DOTFILES, compared by content: `diff` exits 0 when the two trees are the same.
                  [ -d ${filesOf p.base} ] || fail "${p.user}'s base bake realized no home-files tree at all — the comparison would be vacuous"
                  [ -d ${filesOf p.variant} ] || fail "${p.user}'s ${p.label} bake realized no home-files tree at all — the comparison would be vacuous"
                  if diff -r ${filesOf p.base} ${filesOf p.variant}; then
                    echo "${p.user}: home-files are identical across base and ${p.label}"
                  else
                    differed=yes
                  fi

                  # The PACKAGE PROFILE, compared by resolved store path rather than by walking two
                  # closures: a profile is input-addressed, so one package set is one store path and
                  # two paths mean two package sets. Minutes cheaper, same answer.
                  [ -e ${profileOf p.base} ] || fail "${p.user}'s base bake realized no home-path profile at all — the comparison would be vacuous"
                  [ -e ${profileOf p.variant} ] || fail "${p.user}'s ${p.label} bake realized no home-path profile at all — the comparison would be vacuous"
                  if [ "$(readlink -f ${profileOf p.base})" = "$(readlink -f ${profileOf p.variant})" ]; then
                    echo "${p.user}: home-path is the same profile across base and ${p.label}"
                  else
                    differed=yes
                  fi

                  [ -n "$differed" ] || fail "${p.user}'s ${p.label} bake gives the user the SAME dotfiles AND the same package profile as its base bake, yet builds a different activation package — whatever the grant changed, the user does not receive it, and that is what a baked variant is for"
                '') divergent
                + ''
                  touch $out
                ''
              );
          }
        )
      );
    };
}
