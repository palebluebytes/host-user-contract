{
  description = "Reference USER FLEET — the operator's own accounts grouped in ONE repo, each consumed by a host through the contract's pre-built binding. Every user lives under users/, one subdir each: identity.json + user.nix, and whatever home modules that user's declaration points at. This flake is a GENERIC MAPPER over that directory: it hardcodes no user and contributes no module of its own, so adding a user is writing those files. The mode set is the CONTRACT's own (`contract.modes`); the one thing stated here is the per-system HOME MATRIX over it, which is this fleet's topology and nobody else's. Standalone inputs exist only for this repo's own CI; when a host binds a user it supplies the canonical contract + pkgs.";

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
    # No `self`: every home is evaluated ONCE, by the fleet below, and the published names, the
    # binding artifacts and the checks all read THAT.
    {
      nixpkgs,
      contract,
      home-manager,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      # The system this flake publishes its `home-manager switch` surface on. NOT a per-user fact:
      # every user here is buildable on every system the matrix names.
      system = "x86_64-linux";
      # This system's nixpkgs, taken from the FLEET's own per-system memo (below) rather than
      # instantiated a second time here — so the published homes, the binding artifacts and the
      # checks all share the one evaluation the producer already made.
      pkgs = fleet.pkgsBySystem.${system};

      # ── The members, DERIVED from the directory by the CONTRACT ───────────────────────────────
      # `mkMembers` reads the layout and answers, once, who is in this repo:
      # `{ <name> = { name; dir; identity; declaration; }; }`, one member per subdir of ./users/
      # holding an identity.json. Derived, never listed: adding `users/<new>/{identity.json,user.nix}`
      # needs no edit to this file — the homes for every mode, both arches' binding artifacts, the
      # checks and the posture guard all follow. Each user's own story lives in the header of its
      # own `user.nix`, because it travels with the user: lifting one out into a standalone repo is
      # a directory move.
      #
      # Note what a member already carries: its DECLARATION, evaluated. That is what lets this file
      # state no user's modes and no user's desktop — the producer reads them off the declaration,
      # and a host reads them off the published index.
      #
      # What is FLEET-level, and so lives here rather than in any user:
      #
      #   - The two CODE-SHARING arrangements, side by side. Sharing home modules and overlays is
      #     PERMITTED, not required, so the optional shape needs a live fixture or it rots. ada,
      #     ben, cleo, svc and admin share no module and no overlay — there is nothing universal to
      #     factor across them, and it keeps each a clean standalone artifact. duo-a and duo-b
      #     import ONE `shared/module.nix` and ONE `shared/overlay.nix`, keyed on
      #     `config.identity.username` so the same code yields per-user data (the
      #     `shared-code-per-user-data` check below proves exactly that). Neither arrangement
      #     reaches sideways between users' DATA.
      #
      #   - The PUBLIC-repo credential posture: every identity.json ships a `$y$` yescrypt hash
      #     rather than `$6$` sha512crypt, because a world-readable hash must be memory-hard. The
      #     reference fleet is what consumers copy, so it models the rule instead of merely citing
      #     it, and `identity-posture` below enforces it. (The cleartexts are published on purpose
      #     — "correct-horse-battery-staple", and "password" for admin — because these are teaching
      #     fixtures.)
      members = contract.lib.mkMembers { usersDir = ./users; };
      # Two projections OF the members, for the sites that want a list rather than the attrset: the
      # member names and the members' identities (the offender probe among the checks, which
      # appends a synthetic identity to the real ones). Projections, never a second derivation of
      # "who is here" or a second read of an identity.json.
      userNames = lib.attrNames members;
      memberIdentities = map (m: m.identity) (lib.attrValues members);

      # ── The home matrix: which MODES, on which system ────────────────────────────────────────
      # `contract.modes` is the contract's own answer to "what session shapes exist?" — today `cli`
      # and `gui`. A home is built for exactly one of them, so N modes give at most N homes per
      # user rather than 2ⁿ; a third mode lands there, with no edit here.
      #
      # That set is an UPPER BOUND, never a per-system building obligation. WHICH of it a system
      # builds is this fleet's topology and nobody else's, so what is stated below is a MODELLED
      # fleet fact — and only the fact. The subtraction and its guards are the CONTRACT's
      # (`mkHomeMatrix`): this file used to hand-write the filter AND hand-write the assert
      # catching its own filter's failure mode, which is not a fleet's business.
      #
      # The fact itself: this reference fleet declares its aarch64 tier headless (the shape a real
      # fleet has — a headless arm builder beside the x86 desktop seats), and so builds `cli` alone
      # there. That is also why every reference user runs in `cli` — not because the producer
      # demands it, but because `examples/fleet`'s headless hosts run the floor and nothing else,
      # and a user with no cli home for them to select is refused at the BIND.
      #
      # Each row states only what its system's seats CANNOT run, per MODE — never a list of what
      # they CAN. An omitted mode is usable, so a contract which gains one builds it EVERYWHERE —
      # aarch64 included — with no edit to this file. The x86_64 row is `{ }` for exactly that
      # reason.
      #
      # The matrix says what a SYSTEM can run; which of those a user runs IN is the user's own
      # declaration, and what gets built is the intersection.
      homeMatrix = contract.lib.mkHomeMatrix {
        systems = {
          # The x86_64 desktop seats: every mode the contract names, now and as it grows.
          x86_64-linux = { };
          # The arm tier is a headless builder — no seat there can run a desktop session.
          aarch64-linux.gui = false;
        };
      };

      # ── This repo's home builder ─────────────────────────────────────────────────────────────
      # A THIN partial application of the contract's own `mkContractHome`: the builder owns the
      # composition every producer used to hand-write — the home umbrella, the home baseline, the
      # desktop dotfile, the module THIS MODE's declaration points at, the inline
      # identity/`home.*` module, and the `hostFacts` specialArg.
      #
      # What is fixed here is exactly what is this repo's own: home-manager's builder passed
      # verbatim (the injection that keeps the CONTRACT package-free — it applies a function it
      # never imports) and the `stateVersion` (a required argument precisely because real repos
      # differ). Everything else — which member, which mode, which system's pkgs — is the caller's.
      #
      # `extraSpecialArgs` is deliberately NOT threaded: no user here consumes an external flake.
      # Named rather than inlined so the published homes and the confinement check drive the SAME
      # module set — a check over a separately assembled module set would prove nothing about what
      # ships.
      mkHome =
        {
          # A MEMBER, not a directory and an identity: it carries both plus the declaration,
          # already resolved, so this file hands the builder one value and nothing is read twice.
          member,
          # Which system's nixpkgs to build against — always passed, never defaulted. A default
          # reading this file's own `pkgs` would make the builder depend on the fleet that is built
          # FROM it.
          pkgs,
          # The SESSION SHAPE this home is built for. Defaulted to the contract's own FLOOR rather
          # than to a literal, so the confinement check below — which builds one home per member
          # just to probe its module set, and has no opinion about sessions — names no mode and
          # keeps naming none if the registry's floor ever changes.
          mode ? contract.floorMode,
          extraModules ? [ ],
        }:
        contract.lib.mkContractHome {
          inherit
            member
            mode
            extraModules
            pkgs
            ;
          homeManagerConfiguration = home-manager.lib.homeManagerConfiguration;
          stateVersion = "25.11";
        };

      # ── The fleet: every member × every mode its system's row AND its own declaration allow ──
      # `mkContractFleet` is the whole join between the two derived facts above and this repo's
      # builder. It takes WHO is here (`members`), WHAT each system builds (`homeMatrix`), a
      # nixpkgs FUNCTION, and the builder — and returns the published surface entire:
      # `{ homes; packages; contractUsers; systems; pkgsBySystem; }`.
      #
      # What it replaces here was mechanics rather than choices: the per-home eval loop, the
      # members × system × mode fold, the two output merges, and the derivation of `systems` and
      # the per-system `pkgs`. None of that is a fleet's FACT.
      fleet = contract.lib.mkContractFleet {
        inherit members homeMatrix;
        # PLAIN nixpkgs — the producer contributes NO overlay and NO config. A user's own pkgs is
        # declared by its OWN home: home-manager re-imports nixpkgs inside every home eval and
        # CONCATENATES the home's `nixpkgs.overlays` onto the ones the producer passed, so the duo
        # pair's `shared/overlay.nix` merges rather than replaces. A FUNCTION, not an attrset: the
        # producer applies it once per system and hands back the memo as `pkgsBySystem`, so nixpkgs
        # is instantiated once per system rather than once per user × home × system.
        pkgsFor = sys: nixpkgs.legacyPackages.${sys};
        buildHome =
          {
            member,
            mode,
            pkgs,
          }:
          mkHome { inherit member mode pkgs; };
      };
      # DERIVED from the home matrix, never typed twice. `homes.<system>.<user>.<mode>`, evaluated
      # ONCE, so the published names, the binding artifacts and the checks share one evaluation of
      # each home.
      inherit (fleet) systems homes;

    in
    {
      # `homes.<system>.<user>.<mode>` — the published homes, straight out of the producer. It is a
      # flake output in its own right: system-first, matching every sibling and the shape
      # `nix flake check` validates for per-system outputs. It is what a greeter's `homeBuilder`
      # builds against (`nix build "<src>#homes.<sys>.<user>.<mode>.activationPackage"`), and what a
      # consumer's own checks read. `nix flake show` warns "unknown flake output" for it, exactly
      # as it does for `contractUsers`.
      inherit (fleet) homes;

      # `homeConfigurations` is a PURE home-manager CLI adapter, publishing `<user>-<mode>`.
      # Nothing in the contract reads it — a host binds through `contractUsers` and a greeter
      # builds `homes` — so it exists for one loop only: `home-manager switch --flake .#ada-gui`,
      # which is what someone authoring a home actually runs.
      #
      # The FLAT naming is forced from outside and confined to the one consumer that imposes it:
      # home-manager's CLI wraps the fragment name in quotes before it reaches Nix
      # (`homeConfigurations."ada.gui"`), so no nested spelling can ever resolve. There is no bare
      # `<user>` name, because there is no privileged mode to give it to.
      #
      # On the default system only (other systems' homes are reachable through `homes.<sys>`).
      homeConfigurations = lib.listToAttrs (
        lib.concatMap (
          n:
          map (mode: lib.nameValuePair "${n}-${mode}" homes.${system}.${n}.${mode}) (
            lib.attrNames homes.${system}.${n}
          )
        ) userNames
      );

      # Both of the fleet's published attributes, straight out of the producer — it emits them
      # already nested by system, which is the shape a flake output is.
      #
      # `packages` — the pre-built binding artifacts, one per user × published mode × system. Each
      # is content-addressed and carries `activate` + `contract-manifest.json` (with the `mode`
      # frozen in, which the bind asserts the host actually runs):
      #   - x86_64-linux: <user>-contractPackage-{cli,gui} for a user running in both.
      #   - aarch64-linux: <user>-contractPackage-cli alone — the arm tier runs no desktop.
      #
      # `contractUsers` — the turnkey binding INDEX: `contractUsers.<sys>.<user> =
      # { identity; modes; contractPackages = { <mode> = package; } }`, plain data (no IFD), so a
      # host's `bindContractUser` picks a contractPackage by reading it rather than by building
      # every one of them to inspect a baked manifest — and so a GREETER can read a walk-up user's
      # `modes` with one cheap `nix eval` before it builds anything.
      inherit (fleet) packages contractUsers;

      # ── Checks ──────────────────────────────────────────────────────────────────────────────
      # `checks = fleet.packages`, plus the contract's consumer check kit mapped over the derived
      # members. There are no per-user checks — not "none yet": a user here ships its own files and
      # this mapper carries no hook to pick a check file up with. Everything below is generic over
      # the members, so a new user is covered the moment its directory exists.
      #
      # The first clause is the load-bearing one: a contractPackage build-DEPENDS on its activation
      # package, so building every package builds every home.
      checks = lib.genAttrs systems (
        sys:
        fleet.packages.${sys}
        // lib.optionalAttrs (sys == system) (
          # The whole check kit, folded over the members in ONE call — yielding
          # `home-confinement-<user>` and `home-eval-<user>` per member plus one
          # `identity-posture`, so this file names no check and no user:
          #
          #   - CONFINEMENT, per user: the contract's own suite proves the UMBRELLA declares no
          #     system channel; that says nothing about whether THIS repo's imports smuggled one
          #     back in. The check probes the real `mkHome` above — an out-of-universe option must
          #     be unexpressible while a legitimate home option still evaluates.
          #   - HOME EVALUABILITY, per user: every home this repo publishes for that user, on every
          #     system in `homes`, forces to a derivation. The failing arch is always the one
          #     nothing builds by default here, so an x86_64-only package added to shared content
          #     throws HERE rather than on the aarch64 seat hours later.
          #   - The CREDENTIAL POSTURE over the members' identities, ENFORCED rather than merely
          #     documented: a member added with a `$6$` hash fails the flake check rather than
          #     being noticed in review, or not. `require` has no default anywhere in the kit — the
          #     posture is this repo's own choice, and stating it is the point.
          #
          # The material handed over is the SAME `mkHome` and the SAME `homes` the packages are
          # built from.
          contract.lib.mkMemberChecks {
            inherit pkgs members homes;
            # The confinement probe builds one home per member purely to see what its module set
            # will ACCEPT, so it names no mode and takes the builder's floor default — a session
            # shape is not what this check is about.
            buildHome = member: extraModules: mkHome { inherit member extraModules pkgs; };
            require = "yescrypt";
          }
          // {
            # The proof that the posture check above can actually FAIL. Kept here deliberately, as
            # a teaching extra a real users repo does not carry: a posture check that passes
            # because its identity list is empty reads identically to one that passes on merit.
            #
            # So: take the REAL derived members, append one synthetic `$6$` offender, and require
            # that the check rejects it. This tests the CALL SITE, not the helper.
            identity-posture-rejects-an-offender =
              let
                # Any real members identity will do as the base — the offender differs from it only
                # in the two fields the posture looks at — so it is taken from the derivation
                # rather than by naming a user this check has no other business knowing.
                someRealIdentity = lib.head memberIdentities;
                offender = someRealIdentity // {
                  username = "sixto";
                  hashedPassword = "$6$PlK5/zSEHPgdAG32$FCvLAFwEDuoUxclrrYNQ4Q1PgQ3F8SSQpCZYiRy5/H0pDp/Ppjtg88cnsJ0t2sjsn.u5sp2NxrGxuzKc/.ctq/";
                };
                rejected =
                  !(builtins.tryEval (
                    contract.lib.mkIdentityPostureCheck {
                      inherit pkgs;
                      identities = memberIdentities ++ [ offender ];
                      require = "yescrypt";
                      name = "identity-posture-offender-probe";
                    }
                  )).success;
              in
              assert lib.assertMsg rejected (
                "identity-posture-rejects-an-offender: a `$6$` identity appended to the real members did "
                + "NOT fail `require = \"yescrypt\"`. The posture check above is therefore vacuous — it "
                + "would pass whatever the members ships. Check that the members derives a non-empty list "
                + "from ./users."
              );
              pkgs.runCommand "identity-posture-rejects-an-offender" { } "touch $out";

            # The claim the duo pair exists to prove: SHARED CODE, PER-USER DATA. Also kept
            # deliberately as a teaching extra — it is the one check here that names users, because
            # the arrangement it proves is a property of that pair rather than of the members.
            # "Both homes build" would not prove it: a shared module that baked duo-a's identity
            # into duo-b's home would still build. So this pins the two halves separately, on the
            # REALIZED homes:
            #
            #   shared CODE   — `shared/overlay.nix`'s marker package resolves to the SAME store
            #                   path in both closures (one derivation, not a per-user copy), and it
            #                   is really there: the check RUNS it out of each home-path;
            #   per-user DATA — `shared/module.nix`, keyed on `config.identity.username`, renders
            #                   two DIFFERENT store paths, each carrying its own identity and NO
            #                   trace of the other's.
            #
            # This is also why the check lives here rather than in `conformance/`: it needs both
            # home-manager and nixpkgs, and the contract's synthetic suite has neither.
            shared-code-per-user-data =
              let
                # The floor home of each, so the pair is compared in the mode both certainly run
                # in — the shared arrangement is mode-independent, which is the point.
                duoA = homes.${system}.duo-a.${contract.floorMode};
                duoB = homes.${system}.duo-b.${contract.floorMode};
                # Both halves are read out of the REALIZED activation package, never off the
                # evaluated config: the point is what actually lands in the user's home.
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

            # The property the PER-MODE home system exists for, pinned so it cannot rot back into a
            # manifest-only difference: somewhere in this members a MODE is load-bearing — a user
            # whose homes differ in realized CONTENT across the modes it runs in. A mode is exactly
            # what a bind cannot change, so a fleet whose two modes are content-identical builds a
            # second home for nothing.
            #
            # Members-generic on purpose, unlike `shared-code-per-user-data` above: WHICH user
            # substitutes content per mode is that user's own story, told in its own `user.nix`
            # (today duo-a's, whose two modes name two different modules), so this names no user.
            #
            #   the ASSERT — at least one user's two published homes diverge. Let the per-mode
            #                modules converge and NOTHING diverges: the flake then fails to
            #                evaluate with a named message instead of quietly building twins.
            #   the BUILD  — every diverging pair really differs in what the user RECEIVES: the
            #                realized dotfiles or the realized package profile. The manifest is in
            #                neither, so a difference in the frozen `mode` field cannot satisfy it.
            #
            # Lives inside the `sys == system` clause with the rest, and needs to: the aarch64 row
            # is headless, so it publishes ONE mode and there is no second home there to compare.
            mode-substitution-is-load-bearing =
              let
                # Every (user, non-floor mode) pair the published homes hold on this system, paired
                # against that user's floor home.
                pairs = lib.concatMap (
                  n:
                  let
                    published = homes.${system}.${n};
                  in
                  map (mode: {
                    user = n;
                    inherit mode;
                    floor = published.${contract.floorMode};
                    rich = published.${mode};
                  }) (lib.filter (m: m != contract.floorMode) (lib.attrNames published))
                ) (lib.filter (n: homes.${system}.${n} ? ${contract.floorMode}) userNames);
                # Divergent = the mode reached the BUILD. Compared on drvPath because that is the
                # sharpest test available: two homes of one user that name the same module differ
                # ONLY in `hostFacts.mode`, and land on the very same derivation twice.
                divergent = lib.filter (
                  p: p.floor.activationPackage.drvPath != p.rich.activationPackage.drvPath
                ) pairs;
                # The two places mode-specific content can LAND in a realized home. Both are
                # checked, because either alone would fail the canonical demonstration the other
                # way round: a home substituting `home.file` puts nothing in the profile, and one
                # substituting `home.packages` puts nothing in the dotfiles.
                filesOf = home: "${home.activationPackage}/home-files";
                profileOf = home: "${home.activationPackage}/home-path";
              in
              assert lib.assertMsg (divergent != [ ]) (
                "mode-substitution-is-load-bearing: NO reference user's homes differ across the modes it "
                + "runs in — every home this fleet publishes lands on the same activation package as its "
                + "floor one, so the only thing a `gui` home carries is the `mode` frozen into its "
                + "manifest, and the one mechanism the per-mode build exists for has no worked example. "
                + "Restore the substitution: point a user's two modes at two DIFFERENT modules, each "
                + "carrying the content that session can carry (see users/duo-a/user.nix)."
              );
              pkgs.runCommand "mode-substitution-is-load-bearing" { } (
                ''
                  fail() {
                    echo "mode-substitution-is-load-bearing: $1" >&2
                    exit 1
                  }
                ''
                + lib.concatMapStrings (p: ''
                  # --- ${p.user}: ${contract.floorMode} vs ${p.mode} ---
                  differed=""

                  # The DOTFILES, compared by content: `diff` exits 0 when the two trees are the same.
                  [ -d ${filesOf p.floor} ] || fail "${p.user}'s ${contract.floorMode} home realized no home-files tree at all — the comparison would be vacuous"
                  [ -d ${filesOf p.rich} ] || fail "${p.user}'s ${p.mode} home realized no home-files tree at all — the comparison would be vacuous"
                  if diff -r ${filesOf p.floor} ${filesOf p.rich}; then
                    echo "${p.user}: home-files are identical across ${contract.floorMode} and ${p.mode}"
                  else
                    differed=yes
                  fi

                  # The PACKAGE PROFILE, compared by resolved store path rather than by walking two
                  # closures: a profile is input-addressed, so one package set is one store path and
                  # two paths mean two package sets. Minutes cheaper, same answer.
                  [ -e ${profileOf p.floor} ] || fail "${p.user}'s ${contract.floorMode} home realized no home-path profile at all — the comparison would be vacuous"
                  [ -e ${profileOf p.rich} ] || fail "${p.user}'s ${p.mode} home realized no home-path profile at all — the comparison would be vacuous"
                  if [ "$(readlink -f ${profileOf p.floor})" = "$(readlink -f ${profileOf p.rich})" ]; then
                    echo "${p.user}: home-path is the same profile across ${contract.floorMode} and ${p.mode}"
                  else
                    differed=yes
                  fi

                  [ -n "$differed" ] || fail "${p.user}'s ${p.mode} home gives the user the SAME dotfiles AND the same package profile as its ${contract.floorMode} home, yet builds a different activation package — whatever the mode changed, the user does not receive it, and that is what building per mode is for"
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
