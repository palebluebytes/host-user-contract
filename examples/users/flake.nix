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
      #     `config.contract.identity.username` so the same code yields per-user data (the
      #     `shared-code-per-user-data` proof in ./checks.nix proves exactly that, reported through
      #     that file's `reference-user-fleet-checks`). Neither arrangement reaches sideways
      #     between users' DATA.
      #
      #   - The PUBLIC-repo credential posture: every identity.json ships a `$y$` yescrypt hash
      #     rather than `$6$` sha512crypt, because a world-readable hash must be memory-hard. The
      #     reference fleet is what consumers copy, so it models the rule instead of merely citing
      #     it, and the `identity-posture` check in ./checks.nix enforces it. (The cleartexts are
      #     published on purpose — "correct-horse-battery-staple", and "password" for admin —
      #     because these are teaching fixtures.)
      members = contract.lib.mkMembers { usersDir = ./users; };
      # One projection OF the members, for the single site here that wants a list rather than the
      # attrset: the member names the flat `homeConfigurations` adapter below folds over. A
      # projection, never a second derivation of "who is here" — and the only one this file needs,
      # because the checks module beside it takes the members themselves and projects what it wants.
      userNames = lib.attrNames members;

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
          # than to a literal, so the confinement check in ./checks.nix — which builds one home
          # per member just to probe its module set, and has no opinion about sessions — names no
          # mode and keeps naming none if the registry's floor ever changes.
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
      # `checks = fleet.packages`, plus everything ./checks.nix claims about this fleet — the
      # contract's consumer check kit folded over the derived members, and the teaching extras a
      # real users repo does not carry. The proofs live THERE rather than here, and how many of
      # them there are is that file's business: this one states the fleet's facts, and a proof over
      # them is not one of them.
      #
      # The first clause is the load-bearing one: a contractPackage build-DEPENDS on its activation
      # package, so building every package builds every home.
      checks = lib.genAttrs systems (
        sys:
        fleet.packages.${sys}
        // lib.optionalAttrs (sys == system) (
          # The material handed over is the SAME members, the SAME `mkHome` and the SAME `homes`
          # the packages above are built from, plus the one posture this repo requires of its own
          # identities — a check over a separately assembled module set, or over a second read of
          # ./users, would prove nothing about what ships. Nothing else crosses: ./checks.nix takes
          # an explicit argument list and closes over none of this `let`.
          import ./checks.nix {
            inherit
              lib
              pkgs
              contract
              members
              homes
              system
              ;
            # The confinement probe builds one home per member purely to see what its module set
            # will ACCEPT, so it names no mode and takes the builder's floor default — a session
            # shape is not what that check is about.
            buildHome = member: extraModules: mkHome { inherit member extraModules pkgs; };
            # The PUBLIC-repo credential posture this fleet requires (see the members' note above).
            # Stated here, where the fleet's own facts are, and enforced there.
            require = "yescrypt";
          }
        )
      );
    };
}
