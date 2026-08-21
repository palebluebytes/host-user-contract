# The contract's derivation logic — pure functions over the two registries and their projections.
#
# The public surface is a COIN with two faces and one shared vocabulary:
#
#   producer   `mkMembers` (who is in this users repo) → `mkContractFleet` (build and publish all
#              of them) → `contractUsers.<system>.<user>`, the plain-data binding index.
#   consumer   `bindContractUsers { source; users; }` — one call per host, which
#              reads that index, selects the mode this host runs, and realizes the account.
#
# `mkContractUser`/`mkContractUsers`/`mkContractHome` sit under the fleet for producers whose bake
# is not a full cross-product; `mkContractPackage`/`mkContractPackageForHome`/`bindContractPackage`
# are the INTERNAL package-level kernels every public entry point speaks through.
{
  lib,
  registry,
  modeRegistry,
  manifest,
  grantLib,
  userOptions,
  # How this file phrases every refusal (./diagnostics.nix): one prefix rule, one list rendering,
  # one vacuity rationale. Sites below hand facts, never punctuation. INJECTED rather than imported
  # here, exactly as `grantLib` is, so the module the conformance suite unit-tests through
  # `kit.internal` is the SAME instance this file refuses through (issue #64).
  diag,
}:
let
  inherit (diag) showList showName;

  # ── FEATURE projections ──────────────────────────────────────────────────────────────────────

  # A feature is runtime/greeter-eligible iff it declares no privilegedGroups. The feature is
  # self-describing: checking `f.privilegedGroups == []` is the whole rule, so there is no
  # hand-maintained second list to keep in step with the registry.
  runtimeEligibleFeature =
    feature:
    let
      f = registry.${feature} or { };
    in
    (f.privilegedGroups or [ ]) == [ ];

  # The runtime-eligible feature names — THE SAFE SET. Everything a walk-up user at a greeter gets,
  # and the reason "gui by default" is true without anybody declaring it.
  safeSet = lib.filter runtimeEligibleFeature (lib.attrNames registry);

  # The enabled feature names in a `{ <feature> = bool; }` set, and its inverse. Every grant-shaped
  # value in this file is projected through these two, so a grant, an affordance and a bind
  # argument are one shape read one way.
  grantedNamesOf = grantLib.grantedNames;
  grantsOf = names: lib.genAttrs names (_: true);

  # A per-user entry in `bindContractUsers` holds AFFORDANCES — one key per feature — and a small
  # fixed set of bind SETTINGS in the same attrset, which is what makes `cleo = { containers =
  # true; }` read as well as it does. The price is a name collision that has to be impossible
  # rather than unlikely, so the invariant below makes it unwriteable: adding a feature named
  # `source` fails the contract's own eval, not a consumer's (ADR-0015).
  bindSettings = [ "source" ];
  featureNames =
    assert diag.must {
      ok = lib.intersectLists bindSettings (lib.attrNames registry) == [ ];
      who = "features";
      problem =
        "feature(s) ${showList (lib.intersectLists bindSettings (lib.attrNames registry))} collide "
        + "with a per-user bind setting";
      why =
        "A `bindContractUsers` entry holds affordances and settings in ONE attrset, so a feature "
        + "sharing a name with a setting would be read as the setting and silently confer nothing.";
      fix = "Rename the feature, or rename the setting in `bindSettings` (lib.nix).";
    };
    lib.attrNames registry;

  # ── MODE projections ─────────────────────────────────────────────────────────────────────────

  # The mode names — the contract's whole session-shape vocabulary, read straight off `modes.nix`.
  # This is what a per-system matrix row may name, what a user declares under `contract.<mode>`,
  # and what a home is published under. Modes are mutually exclusive, so N of them yield at most N
  # homes per user rather than 2ⁿ, and there is no combination anywhere downstream to label.
  modeNames = lib.attrNames modeRegistry;

  # floorOf: the ONE mode a registry declares as its FLOOR (ADR-0007) — and the reason `runs` never
  # comes out empty.
  #
  # Takes the registry EXPLICITLY, as `homeMatrixOver` takes its upper bound and for the same
  # reason: the contract's own registry has exactly one floor by construction, so the two failures
  # this guards — none, and more than one — are only demonstrable against a synthetic registry.
  floorOf =
    reg:
    let
      floors = lib.filter (m: reg.${m}.floor or false) (lib.attrNames reg);
    in
    assert diag.must {
      ok = lib.length floors == 1;
      who = "modes";
      problem =
        if floors == [ ] then
          "no mode is the floor (modes: ${showList (lib.attrNames reg)})"
        else
          "more than one mode is the floor: ${showList floors}";
      why =
        "Exactly one mode is the floor: it is what a host runs when it affords nothing and what "
        + "selection falls back to, so a registry with none leaves a headless host running no mode "
        + "at all, and one with two leaves the fallback undecided.";
      fix = "Set `floor = true;` on exactly one entry of `modes.nix`.";
    };
    lib.head floors;

  # The contract's own floor. Read off the registry FLAG, never by name: the selection algorithm
  # below names no mode, so that a literal `"cli"` never makes the flag decorative.
  floorMode = floorOf modeRegistry;

  # runsWith: the modes a host RUNS, from the machine capability it declared (ADR-0009).
  #
  #   runs = { the floor } ∪ { m | m is declared }
  #
  # It FILTERS THE REGISTRY rather than concatenating the declaration, which is what makes the
  # declaration a SET and the floor unexcludable. One property worth naming here because only the
  # code shows it: the answer comes out in REGISTRY order, so no diagnostic's wording below depends
  # on how a host wrote its list.
  #
  # No feature is consulted — the two registries touch nowhere (ADR-0007).
  runsWith = declared: lib.filter (m: m == floorMode || lib.elem m declared) modeNames;

  # selectModeOver: THE SELECTION (ADR-0013), as a kernel over an explicit floor — `runs ∩
  # published`, a non-floor mode wins, two of them is a hard error, otherwise the floor.
  #
  # NO MODE NAME APPEARS IN THE ALGORITHM, which is why the floor is a parameter rather than read
  # from the registry here: a literal would make the registry flag decorative. Both the declarative
  # bind and the greeter select through this one kernel (ADR-0020).
  selectModeOver =
    {
      who,
      subject,
      floor,
      # The modes the host RUNS (`runsWith` of what the machine declared).
      runs,
      # The modes this user PUBLISHES here — the key set of its binding index's contractPackages,
      # which IS its declaration as narrowed by the producer's matrix.
      published,
    }:
    let
      candidates = lib.filter (m: lib.elem m published) runs;
      rich = lib.filter (m: m != floor) candidates;
      # "publishes HERE", because the published set is the user's declaration as this system's home
      # matrix narrowed it — not the whole of what the user can run. The case where they differ has
      # its own error (the matrix-subtraction guard in `bindContractUser`), so by the time this
      # fires the narrowing is not the cause: the user runs nothing this host runs.
      show = "this host runs ${showList runs}; ${showName subject} publishes ${showList published} here";
    in
    if candidates == [ ] then
      diag.stop {
        inherit who;
        problem = "no mode is common to the host and ${showName subject} — ${show}";
        why =
          "A mode is what a home IS, so a mismatch is a REFUSAL rather than a silently lesser home. "
          + "Every SEAT still binds every user: what refuses is an operator naming a user whose "
          + "session shape this host cannot run.";
        fix =
          "Afford the feature that mode is run under, or bind a user that enables one of the modes "
          + "this host runs.";
      }
    else if lib.length rich > 1 then
      diag.stop {
        inherit who;
        problem = "more than one rich mode is available for ${showName subject}: ${showList rich} — ${show}";
        why =
          "Rich modes are incomparable by design — a phone and a desktop are not ordered against "
          + "each other — so a host offering two of them has not said which session it means, and "
          + "no ordering exists here to break the tie.";
        fix = "Narrow the host's affordances, or the user's enabled modes, to one of them.";
      }
    else if rich != [ ] then
      lib.head rich
    else
      floor;

  # The HOME MATRIX kernel: narrow an upper bound of MODES to what each system bakes, and guard the
  # narrowing. `homeMatrixOver` takes the bound explicitly; the public `mkHomeMatrix` below is this
  # closed over the contract's own mode names. INTERNAL, exposed only so the conformance suite can
  # drive a synthetic THREE-mode bound — the propagation this design exists for cannot otherwise be
  # shown until the registry itself grows a third mode.
  #
  # WHICH modes a fleet bakes per system is the consumer's own topology; what the CONTRACT owns is
  # the SHAPE of that declaration, because the failure mode is silent: an omitted mode is a home
  # that is never published, and a host that runs it then binds a lesser one or none at all.
  #
  # So the declaration is per-MODE and OPEN by default: a mode a system's row omits is usable, and
  # a row states only what it takes AWAY. Fail-CLOSED is right where the risk of the unknown is
  # admitting something; fail-OPEN where the risk is omitting it. Under-baking is silent and
  # costly; over-baking wastes build time and nothing else. A contract that gains a MODE therefore
  # bakes it EVERYWHERE — on the restricted systems too — with no edit in any consumer repo.
  homeMatrixOver =
    {
      # The fleet's whole home matrix, in ONE fact: `{ <system> = { <mode> = bool; }; }` — which
      # systems this repo bakes, and, per system, which modes its SEATS can run. A mode a row
      # OMITS is usable (absent ⇒ true), so `{ }` is a system that can run everything the contract
      # names and `{ gui = false; }` is a headless tier. A system absent from the matrix is not
      # baked at all.
      systems,
      # The bound to narrow — the contract's own `modes` for the public entry point.
      upperBound,
    }:
    let
      systemNames = lib.attrNames systems;
      rowOf = sys: systems.${sys};
      settingsIn = sys: lib.attrNames (rowOf sys);
      # The modes a system's seats CANNOT run: the `false` entries of its row, and only those.
      unusableIn = sys: lib.filter (m: !(rowOf sys).${m}) (settingsIn sys);
      # The subtraction itself: drop every mode this system's seats cannot run.
      matrix = lib.genAttrs systemNames (sys: lib.filter (m: !lib.elem m (unusableIn sys)) upperBound);

      malformedRows = lib.filter (sys: !lib.isAttrs (rowOf sys)) systemNames;
      nonBoolIn = sys: lib.filter (m: !lib.isBool (rowOf sys).${m}) (settingsIn sys);
      byNonBool = lib.filter (sys: nonBoolIn sys != [ ]) systemNames;
      # Checked on the KEY whatever the boolean says: `sudo = true` is as much a mistake about what
      # a row names as `sudo = false` is, and reads as though it had been considered.
      nonModesIn = sys: lib.filter (m: !lib.elem m upperBound) (settingsIn sys);
      byNonMode = lib.filter (sys: nonModesIn sys != [ ]) systemNames;
      emptied = lib.filter (sys: matrix.${sys} == [ ]) systemNames;
    in
    # Ordered so a broken declaration reports before any verdict about the modes, most specific
    # first: no systems at all, then a row of the wrong shape, then a non-boolean setting, then a
    # setting that names nothing the contract runs — and only then the one verdict about what IS
    # baked.
    assert diag.must {
      ok = systems != { };
      who = "mkHomeMatrix";
      problem = "the matrix is empty";
      why = diag.vacuity { subject = "matrix"; };
      fix =
        "`systems` is `{ <system> = { <mode> = bool; }; }`: one entry per system this repo builds "
        + "for, `{ }` for a system whose seats can run every mode the contract names.";
    };
    assert diag.must {
      ok = malformedRows == [ ];
      who = "mkHomeMatrix";
      problem = "the row(s) for ${showList malformedRows} are not attrsets";
      fix =
        "Each system's row is `{ <mode> = bool; }`, and `{ }` for a system that can run every mode "
        + "the contract names.";
    };
    assert diag.must {
      ok = byNonBool == [ ];
      who = "mkHomeMatrix";
      problem = "non-boolean mode setting(s): ${diag.showPer nonBoolIn byNonBool}";
      why = "Each mode in a row is a BOOL — `false` where that system's seats cannot run it.";
      fix = "An omitted mode is usable, so a row states only what it takes away.";
    };
    assert diag.must {
      ok = byNonMode == [ ];
      who = "mkHomeMatrix";
      problem = "setting(s) that are not MODES: ${diag.showPer nonModesIn byNonMode}";
      why =
        "The modes of this contract are ${showList upperBound} — a home is built for exactly one "
        + "of them. A FEATURE (`sudo`, `gui`) names a grant, which rides the bind and never keys a "
        + "home at all, so the system would build every mode while reading as restricted.";
      fix = "Name the MODES a system's seats cannot run.";
    };
    assert diag.must {
      ok = emptied == [ ];
      who = "mkHomeMatrix";
      problem = "system(s) ${diag.showPer unusableIn emptied} build NO home at all";
      why =
        "Those modes cut every entry of the upper bound ${showList upperBound}. "
        + diag.vacuity {
          subject = "row";
          verbs = "publish, bind and check";
        };
      fix = "Leave a system out of the matrix entirely if this fleet does not build for it.";
    };
    matrix;

  # mkHomeMatrix: the PUBLIC per-system home matrix — `homeMatrixOver` closed over the contract's
  # own mode names, which is what makes a registry that gains a mode reach every consumer's
  # published homes with no edit. Returns `{ <system> = [ <mode> ]; }` — a system's MODES, not a
  # row: a row is the `{ <mode> = bool; }` a fleet declares INTO this.
  mkHomeMatrix =
    { systems }:
    homeMatrixOver {
      inherit systems;
      upperBound = modeNames;
    };

  # ── THE USER DECLARATION ─────────────────────────────────────────────────────────────────────

  # THE USERS-REPO LAYOUT, spelled once: a users directory holds one subdirectory per user, and
  # each holds that user's `identity.json` + `user.nix`. Every site that must name one of those
  # paths reads it through these three, so the layout is ONE edit. They are also why the join is
  # spelled one way: path concatenation, never string interpolation of the directory (which would
  # coerce it into a store path at a different moment than its siblings).
  memberDirIn = usersDir: name: usersDir + "/${name}";
  identityFileIn = memberDir: memberDir + "/identity.json";
  userFileIn = memberDir: memberDir + "/user.nix";

  # evalUserFile: a user's DECLARATION, evaluated against the contract's own schema.
  #
  # This is the whole of the user's voice, and it is read as DATA: bare `evalModules` with no
  # home-manager present, so the producer learns which modes a user runs — and a greeter learns the
  # same thing from a plain `nix eval` — without building anything. `configuration` is a
  # deferredModule, so reading the declaration never forces a home.
  #
  # Typed off the mode registry (`./contract-user.nix`), with no freeform: a user naming a mode
  # this contract does not have is an eval error in the user's OWN repo, at the moment they write
  # it, rather than a user nothing can bind — discovered later by a host operator.
  evalUserFile =
    userFile:
    (lib.evalModules {
      modules = [
        userOptions
        userFile
      ];
    }).config.contract;

  # The modes a declaration ENABLES — its enabled-name projection, exactly the move `grantedNamesOf`
  # makes for a grant set, and the only shape anything downstream consumes.
  enabledModesOf = decl: lib.filter (m: decl.${m}.enable) modeNames;

  # THE UNTOUCHED declaration — the schema evaluated with no definitions at all. Every mode key and
  # every parameter is ALWAYS present on an evaluated declaration (the schema is fully typed and
  # carries no freeform), so "did this user configure the gui mode?" cannot be answered by key
  # presence, only by comparison against this. Derived from the same option module the declaration
  # is evaluated against, so the baseline cannot drift from the schema.
  untouchedDeclaration = (lib.evalModules { modules = [ userOptions ]; }).config.contract;

  # The declaration, plus the two guards every reader of it depends on.
  declarationOf =
    { username, userFile }:
    let
      decl = evalUserFile userFile;
      enabled = enabledModesOf decl;
      # What a mode SAYS, apart from whether it is on: its home and its own parameters.
      settingsOf = d: m: builtins.removeAttrs d.${m} [ "enable" ];
      # A mode configured but never enabled. Nothing will ever build it, so its home and its
      # parameters are dead data in the user's own repo — the one class of mistake a fully-typed
      # schema cannot catch by itself, because every value here is individually well-formed.
      dead = lib.filter (
        m: !decl.${m}.enable && settingsOf decl m != settingsOf untouchedDeclaration m
      ) modeNames;
    in
    # Ordered so the emptier mistake reports first: a user that runs nowhere at all, then one that
    # configured a session it does not run in.
    assert diag.must {
      ok = enabled != [ ];
      who = "contract user";
      problem = "${showName username} enables no mode (in ${toString userFile})";
      why =
        "A user that can run in no session shape is uninstallable: nothing is published for it, so "
        + "every host that tried to bind it would find an empty index entry rather than a refusal.";
      fix =
        "Enable at least one, e.g. `contract.gui.enable = true;` for an ordinary desktop user "
        + "(the modes are ${showList modeNames}).";
    };
    assert diag.must {
      ok = dead == [ ];
      who = "contract user";
      problem =
        "${showName username} configures ${showList dead} without enabling "
        + "${if lib.length dead == 1 then "it" else "them"} (in ${toString userFile})";
      why =
        "A mode that is not enabled is never built, so its `configuration` and its parameters can "
        + "never reach any host — dead data in the user's own repo, and the likeliest reading is "
        + "that the `enable` line was forgotten.";
      fix = "Enable the mode, or drop what it carries.";
    };
    decl;

  # ── THE ACCOUNT ──────────────────────────────────────────────────────────────────────────────

  # The system account fragment a bind PRODUCES: WHO the user is, WHICH features this host
  # conferred, and WHICH session shape it was bound in. A feature has no parameters, so there is
  # nothing else about a grant to carry; the MODE is here because the account needs it — a
  # graphical session's input groups ride the mode rather than a grant, and `accountPlan` unions
  # every group source in one place.
  mkUserAccount =
    {
      identity,
      grants,
      mode,
    }:
    {
      inherit identity mode;
      granted = grants;
    };

  # ── THE PACKAGE-LEVEL KERNELS ────────────────────────────────────────────────────────────────

  # mkContractPackage: assemble the pre-built binding artifact from an already-evaluated home. The
  # user's CI calls this (through the producer surface) and publishes the result; the host pins it
  # as a flake input. `activationPackage` is the home-manager activation package (has
  # `$out/activate`); `packages` is the list of package derivations from `home.packages` —
  # pname/name is extracted for the manifest, since the host needs names, not store paths;
  # `username` is the account name; `mode` is the session shape the home was BUILT for, frozen into
  # the manifest so a host can prove it actually runs that mode.
  #
  # The manifest is serialized to a store path at EVAL TIME via the `manifest` module's
  # `writeManifest` (`builtins.toFile`, pure, no IFD), then copied into the derivation during the
  # build. The manifest module OWNS the schema; this producer only projects its inputs into that
  # shape. The derivation is content-addressed: the same home eval always produces the same path.
  mkContractPackage =
    {
      pkgs,
      activationPackage,
      packages,
      username,
      mode,
    }:
    let
      packageNames = map (p: p.pname or (builtins.parseDrvName p.name).name) packages;
      manifestFile = manifest.writeManifest {
        inherit username mode;
        packages = packageNames;
      };
    in
    pkgs.runCommand "contract-package-${username}" { } ''
      mkdir -p $out
      cp ${activationPackage}/activate $out/activate
      chmod +x $out/activate
      cp ${manifestFile} $out/${manifest.manifestFileName}
    '';

  # mkContractPackageForHome: the home-manager producer adapter over the kernel above. It does NOT
  # import home-manager — it only READS attributes off an already-evaluated `home`
  # (`activationPackage`, `config.home.{packages,username}`), never importing the builder — so the
  # contract stays free of a home-manager dependency. `pkgs` stays a parameter so one call emits
  # packages for more than one system.
  #
  # `mode` is carried through to the manifest and nothing else, and it is REQUIRED: a published
  # artifact always belongs to a mode, so a default would only let one be published claiming none.
  mkContractPackageForHome =
    {
      home,
      pkgs,
      mode,
    }:
    mkContractPackage {
      inherit pkgs mode;
      username = home.config.home.username;
      activationPackage = home.activationPackage;
      packages = home.config.home.packages;
    };

  # ── WHO A CALL IS ABOUT ──────────────────────────────────────────────────────────────────────

  # Resolved ONCE, for every public producer. Each takes either a `member` (a `mkMembers` entry,
  # which already carries the resolved identity and declaration) or the pieces to build one —
  # `name` + `usersDir` for the coin, `memberDir` for the home builder — because one user is not a
  # member set, and a single-user repo must bake without constructing one.
  #
  # One rule: **a member answers every field, and a field passed beside a member must agree with
  # it.** Nothing is silently overridden — a disagreement is how one user's material reaches an
  # output under another's name.
  #
  # The four fields resolve independently and LAZILY, so each caller forces only what it uses, and
  # an unresolvable field is a named error only where it is actually needed.
  resolveMember =
    {
      # The public function name, for the errors. This helper is never called directly, so naming
      # itself would name a function the caller has not heard of.
      context,
      # How THIS caller can be handed a user directory, in its own argument names — the coin takes
      # `usersDir` + `name`, the builder takes `memberDir`, and neither accepts the other's. A
      # shared resolver must not tell a caller to pass an argument that function does not have.
      dirRoutes,
      # Kit-injected, via the caller: the single identity loader.
      loadIdentity,
      member ? null,
      name ? null,
      usersDir ? null,
      memberDir ? null,
      identity ? null,
    }:
    let
      restates =
        field: passed: mine:
        if passed == null || passed == mine then
          mine
        else
          diag.stop {
            who = context;
            problem = "the `${field}` passed disagrees with the member's";
            why =
              "A member is the resolved answer to who this user is — the name its outputs are "
              + "published under, the directory its declaration is read from, and the identity "
              + "both carry — so a field beside it may restate that answer but never replace it.";
            fix = "Pass the member alone, or a `${field}` that matches it.";
          };
      unresolvable =
        field: hint:
        diag.stop {
          who = context;
          problem = "there is no `${field}` to work from";
          fix = "Pass a `member` (a `mkMembers` entry, which carries all of them), or ${hint}.";
        };
      dir =
        if member != null then
          restates "memberDir" memberDir member.dir
        else if memberDir != null then
          memberDir
        else if usersDir != null && name != null then
          memberDirIn usersDir name
        else
          unresolvable "user directory" dirRoutes;
      resolvedName =
        if member != null then
          restates "name" name member.name
        else if name != null then
          name
        else
          unresolvable "name" "the `name` this user's outputs are published under";
    in
    {
      inherit dir;
      name = resolvedName;
      identity =
        if member != null then
          restates "identity" identity member.identity
        else if identity != null then
          identity
        else
          loadIdentity (identityFileIn dir);
      # The user's own declaration. Taken off the member when there is one (so a users repo reads
      # each `user.nix` once per evaluation), otherwise evaluated from the directory. It carries
      # the enable-at-least-one-mode guard with it, which is why no caller repeats that check.
      declaration =
        if member != null then
          member.declaration
        else
          declarationOf {
            username = if name != null then name else toString dir;
            userFile = userFileIn dir;
          };
    };

  # mkMembers: the contract's ONE answer to "who is in this users repo, and what does each one
  # say" — the directory layout, stated once. Given a `usersDir`, it returns
  # `{ <name> = { name; dir; identity; declaration; }; }`: every subdirectory holding an
  # `identity.json` is a MEMBER, keyed by its directory name, carrying that directory, the identity
  # resolved through the contract's single loader, and its evaluated declaration.
  #
  # It is the single resolution SITE as well as the single loader (ADR-0005): a member is what the
  # producer coin and the home builder take, so nothing downstream re-derives a path from a name,
  # and each `identity.json` and each `user.nix` is read exactly once per evaluation.
  #
  # LIFTABILITY is preserved: this reads `users/<u>/` and nothing else — no index file, no
  # manifest, no knowledge at the users-repo root — so lifting one user out into its own repo stays
  # a literal directory move.
  #
  # A directory whose `user.nix` has landed but whose `identity.json` has not is a half-added user
  # and is SKIPPED, as is a non-directory entry (a README, a shared/ sibling). What is NOT skipped
  # is the whole directory yielding nothing (ADR-0022): everything downstream maps over the
  # members, so an empty one bakes, publishes and checks NOTHING while every output stays green.
  mkMembers =
    {
      # Kit-injected (a caller never passes it): the identity.json loader.
      loadIdentity,
      # The users directory — the parent of the per-user subdirectories.
      usersDir,
    }:
    let
      entries = builtins.readDir usersDir;
      names = lib.filter (
        n: entries.${n} == "directory" && builtins.pathExists (identityFileIn (memberDirIn usersDir n))
      ) (lib.attrNames entries);
    in
    assert diag.must {
      ok = names != [ ];
      who = "mkMembers";
      problem =
        "${showName usersDir} holds no member — no subdirectory of it has an `identity.json`. "
        + "Entries seen: ${showList (lib.attrNames entries)}";
      why = diag.vacuity { subject = "member set"; };
      fix = "A users directory is the layout `users/<u>/{identity.json,user.nix}`.";
    };
    lib.genAttrs names (
      name:
      let
        dir = memberDirIn usersDir name;
      in
      {
        inherit name dir;
        identity = loadIdentity (identityFileIn dir);
        declaration = declarationOf {
          username = name;
          userFile = userFileIn dir;
        };
      }
    );

  # ── THE PRODUCER ─────────────────────────────────────────────────────────────────────────────

  # mkContractHome: the producer HOME builder — the contract-owned composition every producer would
  # otherwise hand-write. It is package-free by INJECTION: the consumer passes home-manager's own
  # entry point (`homeManagerConfiguration`) verbatim, and the contract only composes the arguments
  # and applies the function it never imports.
  #
  # It builds a home for ONE MODE, and the module it builds is the one THAT mode's declaration
  # points at (`contract.<mode>.configuration`) — the reason the declaration is keyed by mode at
  # all (ADR-0010, ADR-0012).
  #
  # THE DESKTOP DOTFILE IS COMPOSED BY DEFAULT (ADR-0021): a mode with no `desktop` parameter, or
  # an empty one, writes nothing and costs that home nothing.
  #
  # What stays consumer-side BY DESIGN: `pkgs` (each home layers its own overlays/config, and the
  # platform is read off it), `stateVersion` (a consumer fact — real repos differ — so no contract
  # default), and the two open seams `extraModules` and `extraSpecialArgs`. `hostFacts` is
  # contract-owned and WINS over any `extraSpecialArgs` entry: the mode a home was built for is the
  # contract's own fact, so a caller cannot hand a home a different one by spelling the specialArg
  # itself.
  mkContractHome =
    {
      # Kit-injected (a caller never passes these): the home umbrella, the baseline, the desktop
      # dotfile writer, and the identity.json loader behind `identity`'s default.
      homeModule,
      homeBaselineModule,
      homeDesktopModule,
      loadIdentity,
      # THE INJECTION SURFACE: home-manager's own builder, passed verbatim.
      homeManagerConfiguration,
      # Per-user pkgs — consumer-side by design; also the source of `platform`.
      pkgs,
      # A member (see mkMembers): supplies the user's directory, its already-resolved identity, and
      # its declaration, so a producer that has a member set hands this one value and nothing is
      # resolved a second time.
      member ? null,
      # The user's subdir — the shape a single-user repo (or a hand-driven build) keeps. Given
      # BESIDE a member it may restate it but not contradict it.
      memberDir ? null,
      identity ? null,
      # THE SESSION SHAPE this home is built for, handed to the home as `hostFacts.mode`.
      mode,
      # REQUIRED consumer fact — real repos differ, so the contract carries no default.
      stateVersion,
      # The open seam: everything that makes one producer's homes differ from another's.
      extraModules ? [ ],
      # Opaque passthrough; `hostFacts` is contract-owned and wins (see above).
      extraSpecialArgs ? { },
    }:
    let
      # Who this home is for, and what they said — the same resolution the producer coin runs.
      who = resolveMember {
        context = "mkContractHome";
        dirRoutes = "`memberDir`, the user directory holding this user's `user.nix`";
        inherit
          loadIdentity
          member
          memberDir
          identity
          ;
      };
      username = who.identity.username;
      # This mode's own declaration: the home to build, and that session's parameters.
      forMode =
        who.declaration.${mode} or (diag.stop {
          who = "mkContractHome";
          problem = "${showName mode} is not a mode of this contract";
          fix = "The modes are ${showList modeNames}.";
        });
    in
    assert diag.must {
      ok = forMode.enable;
      who = "mkContractHome";
      problem = "${showName username} does not run in ${showName mode}";
      why =
        "A home is built from that mode's own `configuration`, so building one the user never "
        + "enabled would publish an empty home under a session shape the user does not run.";
      fix = "Set `contract.${mode}.enable = true;` in this user's `user.nix`, or build another mode.";
    };
    homeManagerConfiguration {
      inherit pkgs;
      modules = [
        homeModule
        homeBaselineModule
        (homeDesktopModule (forMode.desktop or ""))
        forMode.configuration
        {
          identity = who.identity;
          home.username = username;
          # A fixed contract rule, not a knob: the realized account lands at the same path (the
          # normal-user default the realization keeps, and the literal the greeter's provision
          # writes), so home and account can never disagree about where home is.
          home.homeDirectory = "/home/${username}";
          home.stateVersion = stateVersion;
        }
      ]
      ++ extraModules;
      extraSpecialArgs = extraSpecialArgs // {
        # THE FACTS this home is handed, and the whole of them:
        #
        #   mode      the session shape it was BUILT for.
        #   platform  the system it is built for, read off the caller's own `pkgs`.
        #   exposed   false, because a pre-built home is built per MODE, not per host: which seat
        #             eventually binds it, and whether that seat is exposed, is unknowable here.
        #
        # `granted` is deliberately ABSENT. No grant can affect a home, so showing one the grant
        # set would be showing it something it must not use.
        hostFacts = {
          inherit mode;
          exposed = false;
          platform = pkgs.stdenv.hostPlatform.system;
        };
      };
    };

  # mkContractUser: the SINGULAR turnkey PRODUCER — the producer twin of the consumer's
  # `bindContractUser`. A single-user repo calls it once; `mkContractUsers` is nothing but this
  # mapped over a member set. It bakes ONE user's homes and emits the flake-output shape a host
  # consumes — ready to `inherit … packages contractUsers`:
  #
  #   - the named packages `<user>-contractPackage-<mode>`, and
  #   - the pure `contractUsers.<sys>.<user>` BINDING INDEX entry
  #     `{ identity; modes; contractPackages = { <mode> = package; }; }`.
  #
  # The index is plain data, so a host's `bindContractUser` selects by READING it — never by
  # building every home to inspect a baked manifest.
  #
  # `modes` is everything the user's declaration enables; `contractPackages` is what this SYSTEM
  # published, which is that set as the producer's home matrix narrowed it. Both are carried
  # because their difference is exactly what the bind's matrix-subtraction guard names — a mode a
  # host runs and a user enables, which this system did not build.
  #
  # AN EMPTY `homes` IS NOT AN ERROR — the matrix is fail-OPEN on coverage and the refusal belongs
  # at the bind (ADR-0012, ADR-0013). The index entry says so plainly: `modes` names what the user
  # runs, and `contractPackages` is empty.
  mkContractUser =
    {
      loadIdentity,
      pkgs,
      # A member (see mkMembers). Supplies the name, the identity and the declaration.
      member ? null,
      # The user's name + directory, for a caller with no member set. Passing either BESIDE a
      # member is allowed only while the two agree.
      name ? null,
      usersDir ? null,
      # `{ <mode> = home; }` — the homes this system built for this user.
      homes,
    }:
    let
      # The system the outputs are keyed by, read off the caller's own `pkgs` — the same rule
      # `mkContractHome` and `bindContractUser` apply, so a caller cannot key its packages by a
      # system its `pkgs` was not built for.
      system = pkgs.stdenv.hostPlatform.system;
      who = resolveMember {
        context = "mkContractUser";
        dirRoutes = "`usersDir` beside the `name`, to resolve this user's directory under";
        inherit
          loadIdentity
          member
          name
          usersDir
          ;
      };
      inherit (who) identity;
      userName = who.name;
      modes = enabledModesOf who.declaration;
      builtModes = lib.attrNames homes;
      # A home under a mode the user does not run has nothing to be: its `configuration` would be
      # empty and no host could ever select it, so it is a mistake in the producer's own fold
      # rather than a home to publish.
      unrun = lib.subtractLists modes builtModes;
    in
    assert diag.must {
      ok = lib.isAttrs homes;
      who = "mkContractUser";
      problem = "`homes` is not an attrset";
      fix = "It is `{ <mode> = home; }`, keyed by the mode each home was built for.";
    };
    assert diag.must {
      ok = userName == identity.username;
      who = "mkContractUser";
      problem =
        "${showName userName} publishes an identity whose username is " + "${showName identity.username}";
      why =
        "A host binds by the INDEX KEY and gets an account named by the IDENTITY, so a user "
        + "published under one name and realized under another creates an account nobody asked "
        + "for: an operator writing `username = ${showName userName}` reads it as the account "
        + "they are creating. The directory a user lives in and the username in its identity.json "
        + "are two spellings of one answer, and they have to agree.";
      fix =
        "Rename the directory to ${showName identity.username}, or set "
        + "`\"username\": \"${userName}\"` in its identity.json.";
    };
    assert diag.must {
      ok = unrun == [ ];
      who = "mkContractUser";
      problem =
        "${showName userName} was handed home(s) for ${showList unrun}, which its `user.nix` does "
        + "not enable (it enables ${showList modes})";
      why =
        "A mode the user does not run has no `configuration` to build from, so publishing it would "
        + "put an empty home under a session shape no host could ever select.";
      fix = "Build only the modes the user enables, or enable those modes in its `user.nix`.";
    };
    let
      built = lib.mapAttrs (mode: home: mkContractPackageForHome { inherit pkgs home mode; }) homes;
    in
    {
      packages.${system} = lib.mapAttrs' (
        mode: package: lib.nameValuePair "${userName}-contractPackage-${mode}" package
      ) built;
      contractUsers.${system}.${userName} = {
        inherit identity modes;
        contractPackages = built;
      };
    };

  # mkContractUsers: the MEMBER-SET convenience — `mkContractUser` mapped over a whole multi-user
  # repo and its outputs merged, so a users flake bakes its entire member set in ONE call. Adds no
  # logic of its own beyond the fold; the per-user bake, naming and index shape all live above.
  #
  # `homes` keys stay the caller's own list because WHICH members it builds homes for, and which
  # homes, is the producer's topology. A key the member set does NOT hold is the other story: that
  # is a hand-listed name that has drifted from the directory, so it is a named error rather than
  # baking for nobody.
  mkContractUsers =
    {
      loadIdentity,
      pkgs,
      members ? null,
      usersDir ? null,
      homes,
    }:
    let
      # Read off `pkgs`, as in `mkContractUser` — this only merges what that emits, so the two
      # cannot key their outputs by different systems.
      system = pkgs.stdenv.hostPlatform.system;
      memberFor =
        name:
        if members == null then
          null
        else
          members.${name} or (diag.stop {
            who = "mkContractUsers";
            problem =
              "${showName name} is not a member — its `homes` entry names somebody the users "
              + "directory does not hold (members: ${showList (lib.attrNames members)})";
            why =
              "A `homes` key is a member to build for, so a name that has drifted from the "
              + "directory is an error, not an empty build.";
          });
      outs = lib.mapAttrsToList (
        name: userHomes:
        mkContractUser {
          inherit
            loadIdentity
            pkgs
            usersDir
            name
            ;
          member = memberFor name;
          homes = userHomes;
        }
      ) homes;
    in
    assert diag.must {
      ok = lib.isAttrs homes;
      who = "mkContractUsers";
      problem = "`homes` is not an attrset";
      fix = "It is `{ <user> = { <mode> = home; }; }`, keyed by the member each home set belongs to.";
    };
    assert diag.must {
      ok = homes != { };
      who = "mkContractUsers";
      problem = "`homes` names no user";
      why = diag.vacuity { subject = "`homes`"; };
      fix =
        "Its key set is who this call bakes for — derive it from the member set, which "
        + "`mkMembers` already refuses to leave empty.";
    };
    {
      packages.${system} = lib.foldl' (acc: o: acc // o.packages.${system}) { } outs;
      contractUsers.${system} = lib.foldl' (acc: o: acc // o.contractUsers.${system}) { } outs;
    };

  # mkContractFleet: the FLEET-LEVEL producer — one rung above `mkContractUsers`, owning the
  # residual JOIN a multi-user, multi-system producer is otherwise left holding. Given WHO is here
  # (`members`) and WHAT each system bakes (`homeMatrix`), it builds every member's every mode on
  # every system and emits the whole published producer surface:
  #
  #   { homes; packages; contractUsers; systems; pkgsBySystem; }
  #
  # so `inherit (fleet) packages contractUsers homes;` IS the flake outputs.
  #
  # THE HOME ARRIVES BY INJECTED CLOSURE. `buildHome` is the CONSUMER's, so this function names
  # neither `mkContractHome` nor `stateVersion`, `extraModules` or `extraSpecialArgs`, and never
  # imports home-manager. That keeps three promises at once: the contract stays package-free; a
  # producer threads its own `extraSpecialArgs` without the contract learning what they are; and a
  # home built WITHOUT `mkContractHome` still bakes through here.
  #
  # `buildHome` takes an ATTRSET, `{ member, mode, pkgs }` — three positional arguments in a fixed
  # order would make transposing `mode` and `pkgs` a type error nowhere.
  #
  # `pkgsFor` IS A FUNCTION, not an attrset (ADR-0014). The fold below applies it exactly once per
  # system, and `pkgsBySystem` is RETURNED so the memoization rule is a value a caller can hold
  # rather than a comment it has to trust.
  #
  # THE CROSS-PRODUCT IS NARROWED BY THE USER: every member is built for the modes its system's
  # matrix names AND its own declaration enables (ADR-0012), so only a home somebody could bind is
  # built. A producer whose bake is NOT a full cross-product drops to `mkContractUsers`, which
  # stays PUBLIC for exactly that reason (ADR-0014).
  mkContractFleet =
    {
      # Kit-injected (a caller never passes it): forwarded to `mkContractUsers` below.
      loadIdentity,
      # WHO is in this repo — the `mkMembers` attrset.
      members,
      # WHAT each system bakes — `mkHomeMatrix`'s value, `{ <system> = [ <mode> ]; }`. Its key set
      # is this fleet's `systems`, which is why neither is stated twice.
      homeMatrix,
      # `system -> pkgs`. Applied once per system; see above.
      pkgsFor,
      # `{ member, mode, pkgs } -> home` — the consumer's own builder.
      buildHome,
    }:
    let
      systems = lib.attrNames homeMatrix;
      # `modesOf`, not `rowOf`: a ROW is what a fleet DECLARES to `mkHomeMatrix`
      # (`{ <mode> = bool; }`), and this reads what `mkHomeMatrix` RETURNS — a plain list of the
      # mode names this system builds. They sit either side of one function, so one word for both
      # would be one word for two types.
      modesOf = sys: homeMatrix.${sys};
      # Split by PARTITION rather than by two negated filters: the emptiness verdict below may only
      # be asked of a system it can read, and reporting a MALFORMED entry as "names no home" would
      # name the wrong mistake — so the two sets have to stay exact complements.
      byModesShape = lib.partition (sys: lib.isList (modesOf sys)) systems;
      malformedModes = byModesShape.wrong;
      emptyModes = lib.filter (sys: modesOf sys == [ ]) byModesShape.right;

      # THE MEMO. One application of `pkgsFor` per system, and the guard that the answer is about
      # the system it was asked for rides each entry — so it fires when that system's homes are
      # forced rather than when a caller merely reads `systems`, and a fleet is never charged for
      # instantiating nixpkgs for a system nothing asked about.
      pkgsBySystem = lib.genAttrs systems (
        sys:
        let
          p = pkgsFor sys;
        in
        assert diag.must {
          ok = p.stdenv.hostPlatform.system == sys;
          who = "mkContractFleet";
          problem =
            "`pkgsFor ${showName sys}` returned pkgs for " + "${showName p.stdenv.hostPlatform.system} instead";
          why =
            "The outputs for a system are keyed by the system its own `pkgs` was built for, so "
            + "this fleet would publish one system's homes under another's name.";
          fix =
            "`pkgsFor` answers about the system it is asked for — " + "`sys: nixpkgs.legacyPackages.\${sys}`.";
        };
        p
      );

      # THE JOIN, and the only place it happens: the matrix offers a MODE, the user's declaration
      # decides whether it is one of theirs, and this builds the home for it keyed by that very
      # mode. Nothing is re-keyed and there is no record to pair — the mode a home was built for
      # and the mode it is published under are one key by construction.
      builtEntries = lib.genAttrs systems (
        sys:
        lib.mapAttrs (
          _: member:
          lib.genAttrs (lib.intersectLists (modesOf sys) (enabledModesOf member.declaration)) (
            mode:
            buildHome {
              inherit member mode;
              pkgs = pkgsBySystem.${sys};
            }
          )
        ) members
      );

      # The per-system bake, `mkContractUsers` handed the built entries directly — its `homes`
      # argument IS `{ <user> = { <mode> = home; }; }`, so there is no reshaping between the two.
      # A member whose declaration and this system's row have nothing in common arrives with an
      # EMPTY entry and is published as an index entry carrying no contractPackages, rather than
      # dropped: the matrix is fail-OPEN on coverage, and the refusal belongs at the BIND, where a
      # host meets a user with nothing in common and the selection can name both sides.
      bindings = lib.mapAttrs (
        sys: byMember:
        mkContractUsers {
          inherit loadIdentity members;
          pkgs = pkgsBySystem.${sys};
          homes = byMember;
        }
      ) builtEntries;
    in
    # Grouped by SUBJECT — the member set, then the matrix, then its rows — and within each the
    # same order the rest of this file uses: a shape that cannot be read before anything is read
    # off it, and a fold that would build NOBODY before any verdict about what it built.
    assert diag.must {
      ok = lib.isAttrs members;
      who = "mkContractFleet";
      problem = "the member set is not an attrset";
      fix =
        "It is `mkMembers`'s own value (`{ <name> = { name; dir; identity; declaration; }; }`), "
        + "keyed by member name, not a list of members.";
    };
    assert diag.must {
      ok = members != { };
      who = "mkContractFleet";
      problem = "the member set is empty";
      why = diag.vacuity { subject = "member set"; };
      fix =
        "Derive it from the users directory (`mkMembers { usersDir = ./users; }`), which refuses "
        + "an empty one at the source.";
    };
    assert diag.must {
      ok = lib.isAttrs homeMatrix;
      who = "mkContractFleet";
      problem = "`homeMatrix` is not an attrset";
      fix = "It is `mkHomeMatrix`'s own value, keyed by system: `{ <system> = [ <mode> ]; }`.";
    };
    assert diag.must {
      ok = homeMatrix != { };
      who = "mkContractFleet";
      problem = "`homeMatrix` names no system";
      why = diag.vacuity { subject = "matrix"; };
      fix = "Its key set is the systems this fleet bakes for.";
    };
    assert diag.must {
      ok = malformedModes == [ ];
      who = "mkContractFleet";
      problem = "the `homeMatrix` modes for ${showList malformedModes} are not lists";
      fix = "`mkHomeMatrix` answers each system with a LIST of MODE names — one per home it builds.";
    };
    assert diag.must {
      ok = emptyModes == [ ];
      who = "mkContractFleet";
      problem = "system(s) ${showList emptyModes} name no home at all";
      why = diag.vacuity {
        subject = "system";
        verbs = "build, publish and check";
      };
      fix =
        "Leave a system out of the matrix entirely if this fleet does not bake for it. "
        + "`mkHomeMatrix` refuses a row emptied by declaration at the source.";
    };
    {
      inherit systems pkgsBySystem;
      # `<system>.<user>.<mode>` — the PUBLISHED homes, and a flake output in its own right: this
      # is what a greeter's `homeBuilder` builds against. It is the built set, because the fold
      # builds exactly what is publishable: this system's row ∩ what the user runs in.
      homes = builtEntries;
      # Nested by system, so `inherit (fleet) packages contractUsers;` is the flake outputs. Each
      # system's bake already keys its own outputs by that system, so this only unwraps the key it
      # was going to be looked up under anyway — never a re-keying.
      packages = lib.mapAttrs (sys: b: b.packages.${sys}) bindings;
      contractUsers = lib.mapAttrs (sys: b: b.contractUsers.${sys}) bindings;
    };

  # ── THE CONSUMER ─────────────────────────────────────────────────────────────────────────────

  # bindContractPackage: the INTERNAL package-level kernel `bindContractUser` binds through. It
  # reads the already-built manifest from a pinned store path and realizes the account. No
  # home-manager dependency. Returns a NixOS module the host imports.
  #
  # `contractPackage` must be a realized store path at eval time — in the pre-built workflow it is
  # a pinned flake input already in the store, so reading its JSON is a plain `builtins.readFile`,
  # not IFD. The module references `pkgs` (the host's NixOS pkgs) to build the package-policy
  # profile when `contract.packagePolicy.allowedPrograms` is non-empty.
  #
  # `runs` is the modes THIS HOST runs, derived from its affordances by the caller — the coupling
  # guard below is its only reader, and it takes the set rather than deriving it so this kernel
  # stays a pure function of what it is handed. REQUIRED, with no permissive default: the guard
  # exists for exactly this path, so a default that let a caller opt out would make it inert
  # precisely where it is the only thing looking.
  bindContractPackage =
    {
      contractPackage,
      identity,
      runs,
      grants ? { },
    }:
    { config, pkgs, ... }:
    let
      inherit (identity) username;
      # Read the pinned manifest THROUGH the schema owner, so this consumer never spells the field
      # set or the filename itself.
      parsed = manifest.readManifest "${contractPackage}/${manifest.manifestFileName}";
      allowedPrograms = config.contract.packagePolicy.allowedPrograms;
      userPackages = parsed.packages;
      approvedNames = lib.filter (n: lib.elem n allowedPrograms) userPackages;
      approvedPkgs = lib.filter (p: p != null) (map (n: pkgs.${n} or null) approvedNames);
      # THE COUPLING GUARD: a host may activate a home only if it actually RUNS the mode that home
      # was built for. `bindContractUser`'s selection satisfies it by construction, so this is
      # defense-in-depth for the internal path where the kernel is called directly.
      #
      # It is the mode rather than the grant because that is what a bind cannot fix: a grant not
      # conferred degrades silently by design, whereas a home built for a graphical session,
      # activated on a machine with no display, is a worse answer than an error naming the mismatch.
      guard = diag.must {
        ok = lib.elem parsed.mode runs;
        who = "bindContractPackage";
        problem =
          "the home selected for ${showName username} was built for mode "
          + "${showName parsed.mode}, which this host does not run (it runs ${showList runs})";
        why =
          "A mode is what the home IS, not something a bind confers, so activating it on a host "
          + "that cannot run it degrades into a session the user cannot use.";
        fix =
          "Afford the feature that mode is run under, or bind a user that runs in a mode this host "
          + "runs.";
      };
    in
    {
      # The guard rides the account VALUE, not a wrapping `assert` on this whole attrset: when
      # `contractPackage` is SELECTED from config, a top-level `assert` would force the manifest
      # read while the module system merely probes this module for unrelated options (e.g.
      # `nixpkgs.*` to build `pkgs`), and that read — reaching back through the config-derived
      # package into `pkgs` — is an infinite recursion. Attached to the account, the guard fires
      # whenever `contract.users.<u>` is read (always, via the realization) but never during bare
      # option-key probing. Still a hard eval error on violation.
      contract.users.${username} =
        assert guard;
        mkUserAccount {
          inherit identity grants;
          mode = parsed.mode;
        };
      # A login session that PERSISTS past activation: the home's user systemd services (sd-switch,
      # sops-nix) must keep running after the `runuser -l` activation exits, so the binding lingers
      # the user itself rather than leaving it a per-seat "should".
      users.users.${username}.linger = true;
      # A systemd oneshot service (not system.activationScripts) so it runs after PAM is
      # configured. activationScripts run during the initrd activation phase where runuser/su
      # cannot open /etc/pam.conf yet — a oneshot service executes post-boot under the full
      # systemd environment where PAM is ready. Before= ensures the service completes before
      # multi-user.target, so callers waiting on that target see the home as activated.
      systemd.services."contract-activate-${username}" = {
        description = "Activate contract package for ${username}";
        wantedBy = [ "multi-user.target" ];
        before = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Run the home activation inside a real LOGIN session for the user (root → `runuser -l`),
          # NOT as `User=<u>` with a bare HOME. A REAL home-manager `activate` needs USER, a login
          # PATH, and — for its sd-switch/reloadSystemd step — a running user systemd manager plus
          # XDG_RUNTIME_DIR, all of which pam_systemd provisions on a login session.
          ExecStart = "${pkgs.util-linux}/bin/runuser -l ${username} -c ${contractPackage}/activate";
        }
        // (
          if allowedPrograms != [ ] then
            let
              profileEnv = pkgs.buildEnv {
                name = "contract-profile-${username}";
                paths = approvedPkgs;
                ignoreCollisions = true;
              };
            in
            {
              # After activate, replace ~/.nix-profile with the host-built policy profile
              # (intersection of allowedPrograms and the user's manifest packages), as the user.
              ExecStartPost = "${pkgs.util-linux}/bin/runuser -l ${username} -c '${pkgs.coreutils}/bin/ln -sfn ${profileEnv} /home/${username}/.nix-profile'";
            }
          else
            { }
        );
      };
    };

  # bindContractUser: the turnkey HOST-SIDE bind, and the ENTIRE host-facing surface of this
  # contract. One call per user:
  #
  #   contract.lib.bindContractUser {
  #     source      = users;
  #     username    = "ada";
  #     affordances = { containers = true; };
  #   }
  #
  # It returns a NixOS module that walks ADR-0015's four steps:
  #   1. infers `system` from the host's own `pkgs`, and reads the user's binding index off the
  #      pinned `source` (`contractUsers.<sys>.<user>`, the pure data the producer emitted);
  #   2. reads the MODES this machine runs (ADR-0009);
  #   3. SELECTS the mode (ADR-0013);
  #   4. GRANTS what it afforded. Note what is NOT here: nothing about a display. A graphical
  #      session's input groups follow the selected MODE, so an ordinary desktop user's bind
  #      carries no affordances at all;
  #   5. delegates to the internal `bindContractPackage` kernel with the selected home, the grant,
  #      the index-supplied identity, and the run set its coupling guard checks against.
  #
  # THE AFFORDANCES RIDE THE BIND (ADR-0009): stated at the one site that already names the user,
  # with no host-level default for either to silently inherit.
  bindContractUser =
    {
      # WHERE this user comes from: anything publishing `contractUsers.<system>.<user>`. Usually a
      # pinned users flake, but nothing here requires a flake — the conformance suite hands it a
      # plain attrset, which is why the argument is not called `usersFlake`.
      source,
      username,
      # `{ <feature> = bool; }` — what this host is willing to confer on THIS user. Typed against
      # the registry below rather than by the module system, because it is a function argument
      # rather than an option; an unknown feature name is a typo in the host's own repo and must
      # not silently become "affords nothing".
      affordances ? { },
    }:
    # Apply the inner bindContractPackage module to the current module args and return its config,
    # rather than returning it via `imports`: the selected home depends on `pkgs`, and an `imports`
    # list that depends on the module fixpoint is an infinite recursion. Splicing the inner
    # module's config in directly is legal because it defines only config (no options, no imports)
    # and merely READS config values.
    { config, pkgs, ... }:
    let
      # The host's platform, inferred from the host's own pkgs. Everything this module selects from
      # `system` (the index lookup, hence identity/home) lands in config VALUES, never in this
      # module's top-level option KEYS — so probing the module for an unrelated option (`nixpkgs.*`,
      # to build `pkgs` itself) never forces `system` and there is no config↔pkgs cycle.
      system = pkgs.stdenv.hostPlatform.system;
      unknownAffordances = lib.subtractLists featureNames (lib.attrNames affordances);
      index =
        source.contractUsers.${system}.${username} or (diag.stop {
          who = "bindContractUser";
          problem = "that source publishes no binding index for ${showName username} on ${showName system}";
          fix = "Does it publish `contractUsers.${system}` — and does it hold this user?";
        });
      affordedNames = grantedNamesOf affordances;
      # The modes this MACHINE runs, from the capability it declared once. Deliberately NOT a
      # function of `affordances`: what a box can run is a fact about the box, and what an account
      # may DO is a decision about a person. Reading them from one namespace made a display look
      # like a privilege.
      runs = runsWith config.contract.modes;
      publishedNames = lib.attrNames index.contractPackages;
      # THE MATRIX SUBTRACTION. A mode this host RUNS and this user RUNS IN, which this system's
      # home matrix took AWAY, is a disagreement with no home to bind: the users repo said this
      # system's seats cannot run that mode, and a host on that system affords the feature it is
      # run under. Selection would swallow it — every such mode is absent from `published`, so the
      # fallback quietly picks the floor and activates a terminal home on a graphical seat with NO
      # message. This is why the index carries `modes` as well as `contractPackages`.
      #
      # BEFORE selection, deliberately: when the subtraction empties the published set entirely,
      # the empty-intersection refusal would otherwise fire first and name the wrong cause.
      subtracted = lib.subtractLists publishedNames (lib.intersectLists runs index.modes);
      # …and the mode it binds this user in. The guard rides `mode` rather than the module head:
      # everything selected from `system` must stay inside a config VALUE, or probing the module
      # for an unrelated option forces `system` before `pkgs` exists and the cycle reopens. Riding
      # `mode` also gets the ordering for free — it is forced before selection's own refusals.
      mode =
        assert diag.must {
          ok = unknownAffordances == [ ];
          who = "bindContractUser";
          problem = "affordance(s) that are not features of this contract: ${showList unknownAffordances}";
          why =
            "An affordance names a FEATURE a host confers on an account. A misspelled one would "
            + "silently afford nothing, and the account would come up quietly less powerful than "
            + "the host meant.";
          fix = "The features are ${showList featureNames}.";
        };
        assert diag.must {
          ok = subtracted == [ ];
          who = "bindContractUser";
          problem =
            "this host runs ${showList runs} and ${showName username} runs in "
            + "${showList index.modes}, but ${showList subtracted} is not published for "
            + "${showName system} — the producer's home matrix took it away";
          why =
            "That matrix row is the users repo stating this system's seats CANNOT run that mode, "
            + "while this host affords the feature it is run under. Nothing built the home, so "
            + "binding would fall back to the floor and activate a lesser session with no message "
            + "at all.";
          fix =
            "Stop subtracting that mode for ${showName system} in the producer's `mkHomeMatrix`, "
            + "or stop affording the feature it is run under on this host.";
        };
        selectModeOver {
          who = "bindContractUser";
          subject = username;
          floor = floorMode;
          inherit runs;
          published = publishedNames;
        };
    in
    (bindContractPackage {
      contractPackage = index.contractPackages.${mode};
      inherit (index) identity;
      grants = grantsOf affordedNames;
      inherit runs;
    })
      { inherit config pkgs; };

  # bindContractUsers: a HOST's whole user list, in one call.
  #
  #   contract.lib.bindContractUsers {
  #     source = users;
  #     users = {
  #       ada   = { };                                    # nothing afforded
  #       cleo  = { containers = true; };
  #       admin = { sudo = true; source = otherUsers; };  # …and from somewhere else
  #     };
  #   }
  #
  # It adds no rule of its own: each entry is `bindContractUser`, and the merge is the module
  # system's. What it removes is the repetition (ADR-0015).
  #
  # WHY A NAME IS STILL WRITTEN AT ALL. It is not the account's name — that comes from the user's
  # own `identity.json`, and the two are one answer because the producer refuses to publish a user
  # whose index key and identity disagree. The name here does SELECTION, and `all = true` is the
  # case where a host does not have to choose (ADR-0015).
  bindContractUsers =
    {
      # The default source — anything publishing `contractUsers.<system>.<user>`. Optional only
      # because every user may name its own.
      source ? null,
      # `{ <user> = { <feature> = bool; …settings }; }`. An entry may be empty: on a machine that
      # declares its own modes, an ordinary desktop user needs nothing afforded at all.
      users ? { },
      # Bind EVERY user the default source publishes, not just the ones named below. Off by
      # default, and deliberately so: a users repo holds accounts that belong on some machines and
      # not others (a break-glass admin is the standing example), and binding them everywhere by
      # omission is the kind of mistake that is invisible until it matters.
      all ? false,
    }:
    { config, pkgs, ... }:
    let
      # No `system` is read here, deliberately — see `publishedByDefault`. Each per-user bind reads
      # its own, inside a config value, where it is safe.
      #
      # WHERE each user comes from: its own `source` if it named one, else the default. Stated once
      # so the two guards below and the bind itself cannot disagree about it.
      sourceFor =
        name:
        let
          own = users.${name}.source or null;
        in
        if own != null then
          own
        else if source != null then
          source
        else
          diag.stop {
            who = "bindContractUsers";
            problem = "there is no source for ${showName name}";
            fix =
              "Set a top-level `source`, or give this user its own — "
              + "`${name} = { source = <a users flake>; };`.";
          };
      # WHO gets bound: the named users, plus — when `all` is set — everybody the default source
      # publishes. A user named beside `all` is not a second selection, it is where that person's
      # settings live; and one that names its own `source` is an ADDITION, since the default source
      # never published them.
      #
      # THE ENUMERATION IS SYSTEM-INDEPENDENT, and it has to be. These names become option KEYS
      # (`contract.users.<name>`), so a key set derived from `system` would need `pkgs` before the
      # module system could build `pkgs` — the config↔pkgs cycle every other `system` read in this
      # file is carefully kept inside a config VALUE to avoid. So `all` means "everybody this
      # source publishes, on any system it publishes for".
      #
      # That is exact rather than approximate for anything built by `mkContractFleet`, which maps
      # every member over every system: the key set is identical across them, and only the MODES
      # differ. A hand-rolled producer that published different PEOPLE per system would bind
      # somebody this host has no index for — which is the existing named refusal, one rung down,
      # naming the user and the system.
      publishedByDefault =
        if source == null then
          [ ]
        else
          lib.attrNames (lib.foldl' (a: b: a // b) { } (lib.attrValues (source.contractUsers or { })));
      names = lib.unique ((lib.optionals all publishedByDefault) ++ lib.attrNames users);
      # An entry's AFFORDANCES: everything in it that is not a bind setting. The guard below is what
      # makes that subtraction safe to read — a key that is neither is named, rather than quietly
      # dropped into one bucket or the other.
      affordancesOf = name: builtins.removeAttrs (users.${name} or { }) bindSettings;
      strayIn =
        name: lib.subtractLists (featureNames ++ bindSettings) (lib.attrNames (users.${name} or { }));
      stray = lib.filter (n: strayIn n != [ ]) (lib.attrNames users);
    in
    assert diag.must {
      ok = !(all && source == null);
      who = "bindContractUsers";
      problem = "`all` was set with no `source` to take everybody from";
      fix = "Set a top-level `source`, or name the users individually.";
    };
    assert diag.must {
      ok = stray == [ ];
      who = "bindContractUsers";
      problem = "entry key(s) that are neither a feature nor a bind setting: ${diag.showPer strayIn stray}";
      why =
        "A user's entry holds AFFORDANCES (one key per feature) beside a few settings, so a key "
        + "that is neither would be read as one of them and do nothing. A misspelled feature "
        + "leaves the account quietly less powerful than the host meant.";
      fix = "The features are ${showList featureNames}; the settings are ${showList bindSettings}.";
    };
    assert diag.must {
      ok = names != [ ];
      who = "bindContractUsers";
      problem = "no user is named, and `all` is not set";
      why = diag.vacuity {
        subject = "user list";
        verbs = "bind";
      };
      fix = "Name the users this host binds, or set `all = true` to take everybody its source publishes.";
    };
    lib.mkMerge (
      map (
        name:
        (bindContractUser {
          source = sourceFor name;
          username = name;
          affordances = affordancesOf name;
        })
          { inherit config pkgs; }
      ) names
    );
in
{
  inherit
    safeSet
    modeNames
    floorOf
    floorMode
    selectModeOver
    homeMatrixOver
    mkHomeMatrix
    runsWith
    evalUserFile
    enabledModesOf
    ;

  # WHAT A GREETER AFFORDS: the safe set, which is EMPTY.
  #
  # A greeter does not let an operator choose powers per walk-up user — there is no operator in the
  # loop at 3am — so it affords every runtime-eligible feature and nothing more. Every feature in
  # the registry now carries privileged groups, so that set is empty and **a greeter confers no
  # feature at all**: a stranger gets a session, not powers.
  #
  # The derivation is kept rather than the constant, and the conformance suite asserts the set is
  # empty as a deliberate TRIPWIRE. The day somebody adds a non-privileged feature it will fail,
  # which is exactly when a human should be asked whether a stranger at a login prompt ought to
  # receive it.
  #
  # What a walk-up user DOES get is a session shape, and "gui by default" is now true for the
  # honest reason: a seat with a display declares `contract.modes = [ "gui" ]`, so it runs the gui
  # mode for everybody, and the mode carries its own input groups. Nothing is granted to make that
  # happen, and a seat WITHOUT a display no longer claims otherwise — which the old
  # `greeterRuns = runsFor safeSet` did unconditionally, on every machine.
  greeterAffordances = grantsOf safeSet;

  # The Tier-1 restricted-eval posture: the canonical Nix settings under which a greeter EVALUATES
  # and BUILDS a host-signed (semi-trusted) user home. Tier 1 is vouched-for by the host's
  # signature, not blindly trusted — the build still runs under a restricted eval to contain
  # accidents and, crucially, to keep the repo from WIDENING its own eval posture (a repo cannot
  # self-certify). As nix.conf:
  #   - accept-flake-config = false           the repo's own `nixConfig` is IGNORED — the
  #                                           un-widenable linchpin; without it a Tier-1 flake could
  #                                           relax every setting below by self-declaration.
  #   - restrict-eval = true                  eval may only touch the store + allowed paths/URIs:
  #                                           no `builtins.readFile "/etc/shadow"`, no arbitrary
  #                                           eval-time fetch. Safe because the greeter warms the
  #                                           full input closure (nix flake archive) BEFORE building,
  #                                           so the restricted build needs no eval-time network.
  #   - allow-import-from-derivation = false  no IFD — eval cannot force a build and import its output.
  #   - sandbox = true                        the build itself runs isolated (no network, no host fs).
  # The greeter hands this to the host's `homeBuilder` as NIX_CONFIG (augmenting the seat's
  # /etc/nix/nix.conf, so experimental-features etc. survive), so a naive `nix build` binding gets
  # the floor for free; the host may only ADD restrictions, never remove them.
  tier1EvalConfig = {
    accept-flake-config = false;
    restrict-eval = true;
    allow-import-from-derivation = false;
    sandbox = true;
  };

  # Render a settings attrset to a NIX_CONFIG / nix.conf body (newline-separated `key = value`).
  # Single-sourced so the greeter and the conformance proof apply byte-for-byte the SAME posture.
  renderNixConfig =
    settings:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        n: v: "${n} = ${if lib.isBool v then lib.boolToString v else toString v}"
      ) settings
    );

  inherit
    mkContractPackage
    mkContractPackageForHome
    bindContractPackage
    mkMembers
    mkContractUser
    mkContractUsers
    mkContractFleet
    mkContractHome
    bindContractUser
    bindContractUsers
    ;
}
