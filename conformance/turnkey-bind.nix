# Conformance domain: the turnkey host-side bind — `bindContractUser` and the
# `mkContractUser`/`mkContractUsers` producer coin it is the twin of.
#
# All synthetic: no host repo, no home-manager. A binding index is fabricated as PLAIN DATA, and
# the packages in it are the repo-path fixture `bindContractPackage` already uses — so selection
# reads the index with NO derivation build, and the no-IFD property is structural rather than
# asserted by side effect.
#
# The bind is the WHOLE host-facing surface, and its argument list is the whole host-facing
# vocabulary: which users flake, which user, and what this host affords THAT user. So the claims
# here are about those three and what falls out of them — the grant, the modes the host runs, the
# mode it selects, and the refusals when a host and a user have nothing in common.
{
  lib,
  toolkit,
  bindContractUser,
  bindContractUsers,
  mkContractUser,
  mkContractUsers,
  pkgs,
  system,
}:
let
  inherit (toolkit) eval evalDeclaration referenceUsersDir;
  # The two reference atoms this domain borrows, BY ROLE, through the toolkit's reference seam
  # (./toolkit.nix): the users directory a producer bakes from, and the two people in it whose
  # declarations the coin reads. Nothing here names a path into `examples/` or a person in it.
  inherit (toolkit.referenceUsers) portable cliOnly;
  # The portable user runs BOTH modes, so she is the one every publication claim below is about;
  # the cli-only user is the one a producer can wrongly hand a gui home.
  portableName = portable.name;
  cliOnlyName = cliOnly.name;

  # The repo-path fixture (a plain path, not a derivation) that stands in for a published
  # contractPackage. `bindContractPackage` reads its manifest at eval time — no build, no IFD. It
  # is frozen at `mode = "cli"`, which is why every index below that publishes `gui` reaches for
  # the gui fixture instead: the coupling guard would otherwise refuse the pair, correctly.
  cliFixture = ./fixtures/reference-contract-package;
  guiFixture = ./fixtures/reference-contract-package-gui;
  fixtureFor = mode: if mode == "gui" then guiFixture else cliFixture;

  # A real on-disk identity, reused for the binding index and the account assertions. The portable
  # user declares no privileged group; a second identity below declares `wheel` to prove the clamp
  # still drops a self-declared privileged group.
  portableIdentity = portable.identity;
  # A second identity, so a host can bind two people with different powers. It carries no groups —
  # an identity CANNOT name one, which is what makes "granted nothing ⇒ holds nothing" a structural
  # fact rather than the result of a filter.
  wheelClaimant = portableIdentity // {
    username = "mallory";
    name = "Mallory Claimant";
  };

  # Fabricate a binding index exactly as `mkContractUser` emits it — pure data.
  # `contractPackages` is keyed by MODE, so its KEY SET is what this user publishes HERE (the modes
  # it runs in, as the producer's matrix narrowed them) and selection reads exactly that.
  #
  # `modes` is the user's own declaration, carried beside the publication so the bind can tell a
  # mode the user never ran in from one this system's matrix took away. It DEFAULTS to the
  # published set — the case where the matrix took nothing — so only the subtraction fixture says
  # otherwise.
  mkIndex =
    {
      identity,
      published,
      modes ? published,
    }:
    {
      inherit identity modes;
      contractPackages = lib.genAttrs published fixtureFor;
    };

  # A SOURCE stand-in: only the `contractUsers.<sys>.<user>` surface a bind reads. It is a plain
  # attrset, which is the point of the argument not being called `usersFlake` — nothing here
  # requires a flake.
  sourceFor = username: index: { contractUsers.${system}.${username} = index; };

  # Bind a user via the turnkey path, varying BOTH host dimensions independently:
  #
  #   modes       what this MACHINE can run — a capability of the box, declared once for it
  #   affordances what THIS PERSON may do — a decision, stated at the bind that names them
  #
  # Nothing has to agree between them, which is why they are two arguments here rather than one:
  # they answer different questions, and every claim below that varies one while holding the other
  # still is a claim that they really are independent.
  bindTurnkey =
    {
      index,
      modes ? [ ],
      affordances ? { },
      username ? portableName,
    }:
    eval [
      { contract.modes = modes; }
      (bindContractUser {
        source = sourceFor username index;
        inherit username affordances;
      })
    ];

  # --- (a) THE GRANT IS WHAT THE HOST AFFORDED ---
  # There is no user-side half to intersect with: which powers an account holds is the host's
  # decision alone, taken at the site that already names the user. So a bind that affords
  # containers and sudo confers exactly those, and one that affords neither confers neither — on
  # the SAME user, from the SAME flake.
  bothModesIndex = mkIndex {
    identity = portableIdentity;
    published = [
      "cli"
      "gui"
    ];
  };
  # A gui-capable machine that also confers a privileged power.
  affordedTwo = bindTurnkey {
    index = bothModesIndex;
    modes = [ "gui" ];
    affordances = {
      sudo = true;
      containers = true;
    };
  };
  # …and one that declares nothing and confers nothing.
  affordedNothing = bindTurnkey { index = bothModesIndex; };
  # THE INDEPENDENCE, as a pair: a gui machine that confers NOTHING (an ordinary desktop user's
  # bind — no affordances at all), and a headless machine that confers a privileged power.
  guiNoGrant = bindTurnkey {
    index = bothModesIndex;
    modes = [ "gui" ];
  };
  headlessWithGrant = bindTurnkey {
    index = bothModesIndex;
    affordances.sudo = true;
  };

  # PER-USER, ON ONE HOST: two binds on one machine, two different affordance sets, two different
  # accounts — while the machine capability is stated once and applies to both. This is what
  # moving the affordances onto the bind buys, and it needs no second mechanism.
  twoUsersOneHost = eval [
    { contract.modes = [ "gui" ]; }
    (bindContractUser {
      source = {
        contractUsers.${system} = {
          ${portableName} = bothModesIndex;
          mallory = mkIndex {
            identity = wheelClaimant;
            published = [ "cli" ];
          };
        };
      };
      username = portableName;
    })
    (bindContractUser {
      source = {
        contractUsers.${system} = {
          ${portableName} = bothModesIndex;
          mallory = mkIndex {
            identity = wheelClaimant;
            published = [ "cli" ];
          };
        };
      };
      username = "mallory";
      affordances.sudo = true;
    })
  ];

  # A misspelled affordance would silently afford nothing, and the account would come up quietly
  # less powerful than the host meant. It is a typo in the HOST's own repo, so it is an error.
  unknownAffordance = builtins.tryEval (
    (bindTurnkey {
      index = bothModesIndex;
      affordances = {
        sudoo = true;
      };
    }).contract.users.${portableName}.granted
  );
  # A MODE is not a feature, and naming one as an affordance is the mistake this split makes
  # possible to make — so it is the one the guard has to catch by name. `gui` used to be both.
  modeAsAffordance = builtins.tryEval (
    (bindTurnkey {
      index = bothModesIndex;
      affordances = {
        gui = true;
      };
    }).contract.users.${portableName}.granted
  );

  # --- (b) MODE SELECTION ---
  # Nobody declares a mode. A host affording gui RUNS { cli, gui }, so the rich mode wins; a host
  # affording nothing runs { cli } alone, so selection falls back to the floor.
  selGui = affordedTwo;
  selFloor = affordedNothing;

  # THE REFUSAL: a user publishing gui ALONE, bound by a host that affords nothing. `runs ∩
  # published` is empty, and that is a hard error naming both sets — not a silently lesser home,
  # because a home built for a graphical session activated on a machine with no display is the
  # worse answer.
  guiOnlyIndex = mkIndex {
    identity = portableIdentity;
    published = [ "gui" ];
  };
  noCommonModeEval = builtins.tryEval (
    (bindTurnkey { index = guiOnlyIndex; }).contract.users.${portableName}.granted
  );
  # …and its positive control: the SAME gui-only user on a host that RUNS gui binds fine, so the
  # refusal is about the mismatch and not about publishing one mode.
  guiOnlyOnASeat = bindTurnkey {
    index = guiOnlyIndex;
    modes = [ "gui" ];
  };

  # --- (b2) THE MATRIX SUBTRACTION ---
  # The portable user runs in BOTH modes, but this system's home matrix took gui away, so only cli
  # is published for her here. The host declares gui, so it RUNS gui. Selection alone would answer
  # the floor and activate a terminal home on a graphical seat with no message at all; the guard
  # names the matrix as the cause instead.
  subtractedIndex = mkIndex {
    identity = portableIdentity;
    published = [ "cli" ];
    modes = [
      "cli"
      "gui"
    ];
  };
  subtractedEval = builtins.tryEval (
    (bindTurnkey {
      index = subtractedIndex;
      modes = [ "gui" ];
    }).contract.users.${portableName}.granted
  );
  # The control, and it is what makes the claim above mean anything: the SAME publication on the
  # SAME host, with the user running only in what is published. Nothing was taken away, so the
  # floor binds and the guard stays silent — the refusal is about the SUBTRACTION and not about
  # binding the floor on a gui-affording host, which is ordinary and must keep working.
  unsubtractedBind = bindTurnkey {
    index = mkIndex {
      identity = portableIdentity;
      published = [ "cli" ];
    };
    modes = [ "gui" ];
  };

  # --- (c) the mode coupling guard, reached through the real selection ---
  # Selection satisfies the guard by construction — it can only pick a mode the host runs — so what
  # the turnkey path proves is the accept end: a home whose FROZEN mode is one this host runs
  # binds. The reject end is only reachable by calling the kernel directly, which
  # ./contract-package.nix does.
  frozenModeBind = guiOnlyOnASeat;

  # --- (d) untrusted safety: a self-declared privileged group under a safe affordance ---
  # A machine with a display confers no POWER by having one: mallory is bound on a gui seat and
  # afforded nothing, so she holds no wheel. The control is the other bind in `twoUsersOneHost`,
  # where a host that DOES afford sudo confers it — so the difference is the grant and nothing else.
  malloryClamped = bindTurnkey {
    username = "mallory";
    index = mkIndex {
      identity = wheelClaimant;
      published = [ "cli" ];
    };
    modes = [ "gui" ];
  };

  # --- (e) the producer coin: what it emits, and from what ---
  # A synthetic already-evaluated home (attribute paths mirror a homeManagerConfiguration result),
  # exactly as ./contract-package.nix stands one in for `mkContractPackageForHome`. It carries no
  # `contract.*` at all: a home does not speak outward any more, so what a user publishes is
  # answered from its `user.nix` one level up, before any home exists.
  activationStub = pkgs.runCommand "turnkey-activation-stub" { } ''
    mkdir -p $out
    printf '#!/bin/sh\necho activated\n' > $out/activate
    chmod +x $out/activate
  '';
  syntheticHome = username: {
    activationPackage = activationStub;
    config.home = {
      packages = [ pkgs.hello ];
      inherit username;
    };
  };
  # `{ <mode> = home; }` — what a system BUILT for this user, its matrix row ∩ what she runs in.
  # The portable user's real `user.nix` runs in both, so both are published.
  portableHomes = {
    cli = syntheticHome portableName;
    gui = syntheticHome portableName;
  };
  bindings = mkContractUsers {
    inherit pkgs;
    usersDir = referenceUsersDir;
    homes.${portableName} = portableHomes;
  };
  emittedIndex = bindings.contractUsers.${system}.${portableName};
  # The SINGULAR partner: `mkContractUser` bakes ONE user and must emit byte-identical outputs to
  # the member-set form for that user (`mkContractUsers` is nothing but this mapped over them).
  singleUser = mkContractUser {
    inherit pkgs;
    usersDir = referenceUsersDir;
    name = portableName;
    homes = portableHomes;
  };

  # The cli-only user's real `user.nix` runs in `cli` alone, so a producer handing them a gui home
  # has built something with no `configuration` behind it that no host could ever select. That is a
  # mistake in the producer's own fold, and it must fail the bake rather than publish an empty
  # home.
  unrunModeBake = builtins.tryEval (
    builtins.deepSeq (lib.attrNames
      (mkContractUser {
        inherit pkgs;
        usersDir = referenceUsersDir;
        name = cliOnlyName;
        homes = {
          cli = syntheticHome cliOnlyName;
          gui = syntheticHome cliOnlyName;
        };
      }).packages.${system}
    ) true
  );
  # …and its control: the same user, handed only the mode they run in, bakes.
  runModeBake = mkContractUser {
    inherit pkgs;
    usersDir = referenceUsersDir;
    name = cliOnlyName;
    homes.cli = syntheticHome cliOnlyName;
  };

  # A system baking NONE of a user's modes publishes nothing for that user there — an index entry
  # naming the modes she runs in, with no contractPackages behind it. Not an error: the matrix is
  # fail-OPEN on coverage, and the refusal belongs at the bind, where both sides can be named.
  uncoveredUser = mkContractUser {
    inherit pkgs;
    usersDir = referenceUsersDir;
    name = portableName;
    homes = { };
  };
  # …and that is exactly what the bind then refuses, naming what it runs against what she publishes.
  uncoveredBind = builtins.tryEval (
    (bindTurnkey {
      index = uncoveredUser.contractUsers.${system}.${portableName};
      modes = [ "gui" ];
    }).contract.users.${portableName}.granted
  );

  # --- (f) the coin takes a MEMBER ---
  # A `mkMembers` entry, stood in for by hand so these stay claims about the COIN. Its `identity`
  # and its `declaration` deliberately do NOT match what is on disk under its `dir` (the fixture's
  # own name is the reference one, and her own file runs in both modes), so the index can only
  # carry them if `mkContractUser` stopped resolving `<usersDir>/<name>/` for itself — which is the
  # point: the member set resolved those files once, and the coin reads the member.
  #
  # The `usersDir` + `name` calls above are the same claim from the other side: they still work, so
  # a single-user repo bakes without constructing a member set at all.
  portableMember = {
    inherit (portable) name dir;
    identity = portableIdentity // {
      name = "Rosa Member";
    };
    declaration = evalDeclaration [ { contract.cli.enable = true; } ];
  };
  memberUser = mkContractUser {
    inherit pkgs;
    member = portableMember;
    homes.cli = syntheticHome portableName;
  };
  membersFromMember = mkContractUsers {
    inherit pkgs;
    members.${portableName} = portableMember;
    homes.${portableName}.cli = syntheticHome portableName;
  };

  # The routes OUT of a bake, spelled once, so each guard is probed through the ones it must reach
  # rather than through whichever is handy:
  #
  #   readPackageNames  the published NAMES, derived from the published key set alone.
  #   readPackages      the published DERIVATIONS — what a user repo's own `checks = packages`
  #                     forces. Taken to `outPath` rather than deep-forced: a derivation is a
  #                     recursive attrset, so `deepSeq` over one never terminates.
  #   readIndex         the binding index a host reads.
  readPackageNames = u: lib.attrNames u.packages.${system};
  readIndex = u: u.contractUsers.${system};
  # A member handed alongside a DISAGREEING `name`: the package name and the index key come from
  # `name`, the identity from the member, so this would publish one person's identity under
  # another's name — invisible downstream, since a host binds by the index key it finds.
  mismatched =
    read:
    builtins.tryEval (
      read (mkContractUser {
        inherit pkgs;
        member = portableMember;
        name = cliOnlyName;
        homes.cli = syntheticHome portableName;
      })
    );
  mismatchedIndex = mismatched readIndex;
  mismatchedPackageName = mismatched readPackageNames;
  # A `homes` entry naming somebody the member set does not hold — a hand-listed name that has
  # drifted from the directory. A named error, never a member silently baked from nothing.
  strayEval = builtins.tryEval (
    (mkContractUsers {
      inherit pkgs;
      members.${portableName} = portableMember;
      homes.${cliOnlyName}.cli = syntheticHome cliOnlyName;
    }).contractUsers.${system}.${cliOnlyName}.identity
  );
  # The anti-vacuity guard one rung up: a member fold that collapsed to no users at all would have
  # published, bound and checked NOTHING with every output green.
  noUsersBaked = builtins.tryEval (
    builtins.deepSeq (mkContractUsers {
      inherit pkgs;
      usersDir = referenceUsersDir;
      homes = { };
    }) true
  );
  # --- (g) the PLURAL, and the two things only it can express ---
  # A three-user source, so selection is a real choice rather than "the only one there is".
  threeUp = {
    contractUsers.${system} = {
      ${portableName} = bothModesIndex;
      # A wholly SYNTHETIC third party (the reference fleet is not consulted for this one): the
      # claim is about naming a subset, so what these two need is to exist and to differ.
      bo = mkIndex {
        identity = portableIdentity // {
          username = "bo";
        };
        published = [ "cli" ];
      };
      mallory = mkIndex {
        identity = wheelClaimant;
        published = [ "cli" ];
      };
    };
  };
  # A SECOND source, holding one user the first does not.
  elsewhere = {
    contractUsers.${system}.contractor = mkIndex {
      identity = portableIdentity // {
        username = "contractor";
      };
      published = [ "cli" ];
    };
  };
  boundBy =
    args:
    eval [
      { contract.modes = [ "gui" ]; }
      (bindContractUsers args)
    ];
  # Naming a subset: three published, two bound.
  subset = boundBy {
    source = threeUp;
    users = {
      ${portableName} = { };
      mallory.sudo = true;
    };
  };
  # `all`: everybody the source publishes, with settings for only some of them.
  everyone = boundBy {
    source = threeUp;
    all = true;
    users.mallory.sudo = true;
  };
  # A per-user source: `contractor` is in NEITHER the default source nor `all`'s reach, and is
  # bound anyway because their entry says where they come from.
  mixed = boundBy {
    source = threeUp;
    all = true;
    users.contractor.source = elsewhere;
  };
  strayKey = builtins.tryEval (
    builtins.deepSeq
      (boundBy {
        source = threeUp;
        users.${portableName}.sudoo = true;
      }).users.users
      true
  );
  allWithoutSource = builtins.tryEval (builtins.deepSeq (boundBy { all = true; }).users.users true);
  nobody = builtins.tryEval (builtins.deepSeq (boundBy { source = threeUp; }).users.users true);
  sourceless = builtins.tryEval (
    builtins.deepSeq (boundBy { users.${portableName} = { }; }).users.users true
  );

  # --- (h) the index key must agree with the identity it publishes ---
  # A member published under one name whose identity says another. A host binds by the KEY and gets
  # an account named by the IDENTITY, so this creates an account nobody asked for.
  misnamedBake = builtins.tryEval (
    builtins.deepSeq (lib.attrNames
      (mkContractUser {
        inherit pkgs;
        member = portableMember // {
          identity = portableMember.identity // {
            username = "somebody-else";
          };
        };
        homes.cli = syntheticHome portableName;
      }).contractUsers.${system}
    ) true
  );

in
{
  assertions = [
    # (a) the grant is what the host afforded
    {
      name = "grant: a bind confers exactly what it affords";
      ok =
        let
          g = affordedTwo.contract.users.${portableName}.granted;
        in
        g.sudo && g.containers && !g.virtualization;
    }
    {
      # THE SPLIT, in one claim. A gui machine that affords NOTHING still gives its user a full
      # graphical session — the input groups ride the MODE — while a headless machine that affords
      # `sudo` gives wheel and no session groups at all. Two host dimensions, neither reachable
      # from the other, and the ordinary desktop bind is the one with an empty affordance set.
      name = "machine vs person: a gui machine grants nothing yet seats the user; a headless one grants wheel";
      ok =
        let
          seated = guiNoGrant.users.users.${portableName}.extraGroups;
          powered = headlessWithGrant.users.users.${portableName}.extraGroups;
        in
        lib.all (v: !v) (lib.attrValues guiNoGrant.contract.users.${portableName}.granted)
        && lib.elem "uinput" seated
        && !(lib.elem "wheel" seated)
        && lib.elem "wheel" powered
        && !(lib.elem "uinput" powered);
    }
    {
      # The display surface follows the MACHINE, not any account: the gui machine has one with an
      # empty grant set, and the headless one has none despite conferring a privileged power.
      name = "machine vs person: the display surface follows contract.modes, never a grant";
      ok = guiNoGrant.contract.display.enabled && !headlessWithGrant.contract.display.enabled;
    }
    {
      name = "grant: a bind that affords nothing confers nothing (the host's veto, in its simplest form)";
      ok =
        let
          g = affordedNothing.contract.users.${portableName}.granted;
        in
        !g.sudo && !g.containers;
    }
    {
      # THE PER-USER CLAIM: one host, two binds, two different affordance sets — so the seated user
      # gets gui's input groups and no wheel, while mallory gets wheel and no display surface of
      # her own. No second mechanism, and no host-wide default for either to inherit.
      name = "affordances ride the bind: two users on ONE host hold different powers";
      ok =
        let
          seated = twoUsersOneHost.users.users.${portableName}.extraGroups;
          mallory = twoUsersOneHost.users.users.mallory.extraGroups;
        in
        lib.elem "uinput" seated
        && !(lib.elem "wheel" seated)
        && lib.elem "wheel" mallory
        && !(lib.elem "uinput" mallory);
    }
    {
      name = "affordances: a name that is not a feature of this contract is a hard, named error";
      ok = !unknownAffordance.success;
    }
    {
      # …and specifically a MODE named as an affordance. `gui` used to be both a mode and a
      # feature, so this is the mistake somebody carrying an old host config will actually make,
      # and it must fail by name rather than silently conferring nothing.
      name = "affordances: naming a MODE as an affordance is refused (gui is not a feature)";
      ok = !modeAsAffordance.success;
    }

    # (b) mode selection — nobody declares a mode; `runs` is derived from the affordances
    {
      # A gui-affording host RUNS { cli, gui }, so the rich mode wins over the floor.
      name = "mode selection: a gui-declaring host runs { cli, gui } and binds the gui home";
      ok = selGui.users.users.${portableName}.isNormalUser && selGui.contract.display.enabled;
    }
    {
      # …and one declaring nothing runs { cli } alone, so selection falls back to the floor —
      # without any host having written `cli` anywhere.
      name = "mode selection: a host declaring no mode falls back to the floor";
      ok = selFloor.users.users.${portableName}.isNormalUser && !selFloor.contract.display.enabled;
    }
    {
      # THE REFUSAL: a gui-only user on a headless host has no mode in common with it, and that is
      # a hard error naming both sets. Silent degradation is for GRANTS, never for modes.
      name = "mode selection: a gui-only user on a host running only the floor is a hard error";
      ok = !noCommonModeEval.success;
    }
    {
      # …and its control: the same user on a gui-affording seat binds, so the refusal is about the
      # mismatch and not about publishing one mode.
      name = "mode selection: the same gui-only user binds on a gui-declaring seat (the control)";
      ok = guiOnlyOnASeat.users.users.${portableName}.isNormalUser;
    }

    # (b2) the matrix subtraction — the mode the producer took away from THIS system
    {
      # Distinct from the refusal above, and the distinction is the point: there the user runs in
      # nothing this host runs, and SELECTION refuses. Here selection succeeds and answers the
      # floor, so only a guard reading `modes` beside the publication can see the mistake.
      name = "matrix subtraction: a mode this host runs and this user runs in, unpublished here, is a hard error";
      ok = !subtractedEval.success;
    }
    {
      name = "matrix subtraction: the same publication with nothing subtracted binds the floor (the control)";
      ok = unsubtractedBind.users.users.${portableName}.isNormalUser;
    }

    # (c) the mode coupling guard, reached through the real selection
    {
      name = "coupling guard: a home frozen as `gui` binds on a host that runs gui (accept)";
      ok = frozenModeBind.users.users.${portableName}.isNormalUser;
    }

    # (d) untrusted safety
    {
      name = "untrusted safety: an account afforded nothing holds no wheel, on a seat with a display";
      ok = !(lib.elem "wheel" malloryClamped.users.users.mallory.extraGroups);
    }
    {
      name = "untrusted safety: the same identity DOES get wheel where sudo is afforded (the control)";
      ok = lib.elem "wheel" twoUsersOneHost.users.users.mallory.extraGroups;
    }

    # (e) the producer coin
    {
      name = "mkContractUsers: emits the named package <user>-contractPackage-<mode>";
      ok =
        lib.attrNames bindings.packages.${system} == [
          "${portableName}-contractPackage-cli"
          "${portableName}-contractPackage-gui"
        ];
    }
    {
      name = "mkContractUsers: the binding index carries { identity; modes; modeParams; contractPackages }";
      ok =
        lib.attrNames emittedIndex == [
          "contractPackages"
          "identity"
          "modeParams"
          "modes"
        ]
        && emittedIndex.identity.username == portableName;
    }
    {
      # `modes` is read off the user's own `user.nix`, not off a home: a home does not speak
      # outward, so what a user runs in is answered before any home exists — which is also what
      # lets a greeter learn it from one cheap `nix eval`.
      name = "mkContractUser: the index `modes` is the user's own declaration";
      ok =
        emittedIndex.modes == [
          "cli"
          "gui"
        ];
    }
    {
      # …and `contractPackages` is what this SYSTEM published, keyed by the very mode each home was
      # built for. There is nothing to pair: homes come in keyed by mode and go out keyed by mode.
      name = "mkContractUser: the index is keyed by the PUBLISHED modes, one package each";
      ok =
        lib.attrNames emittedIndex.contractPackages == [
          "cli"
          "gui"
        ]
        && emittedIndex.contractPackages.gui ? outPath;
    }
    {
      name = "mkContractUser: a home for a mode the user does not run in is a hard bake error";
      ok = !unrunModeBake.success;
    }
    {
      name = "mkContractUser: the same user handed only the mode she runs in bakes (the control)";
      ok = runModeBake.contractUsers.${system}.${cliOnlyName}.modes == [ "cli" ];
    }
    {
      # A system baking none of a user's modes publishes nothing THERE, and says so: the entry
      # survives with the modes she runs in and no packages. Refusing here would let one system's
      # topology decide what a self-contained user may BE.
      name = "mkContractUser: a system baking none of a user's modes publishes an empty entry, not an error";
      ok =
        uncoveredUser.contractUsers.${system}.${portableName}.contractPackages == { }
        &&
          uncoveredUser.contractUsers.${system}.${portableName}.modes == [
            "cli"
            "gui"
          ]
        && uncoveredUser.packages.${system} == { };
    }
    {
      # …and the refusal it defers to. This is why the empty entry survives: the bind can name what
      # it runs against what the user publishes, where a missing entry could only say "no such user".
      name = "mkContractUser: binding that empty entry is the refusal, at the bind, naming both sides";
      ok = !uncoveredBind.success;
    }
    {
      name = "mkContractUsers: `homes` naming no user is a hard error, never empty green outputs";
      ok = !noUsersBaked.success;
    }
    {
      # The singular producer is the true per-user partner of bindContractUser: its one-user output
      # must match the member-set form for that user.
      name = "mkContractUser: the singular producer matches mkContractUsers for one user";
      ok =
        (
          singleUser.packages.${system}."${portableName}-contractPackage-gui".outPath
          == bindings.packages.${system}."${portableName}-contractPackage-gui".outPath
        )
        && singleUser.contractUsers.${system}.${portableName} == emittedIndex;
    }

    # (f) the member as the coin's input
    {
      name = "mkContractUser: a member's identity AND declaration reach the index (no path re-derived)";
      ok =
        memberUser.contractUsers.${system}.${portableName}.identity.name == "Rosa Member"
        && memberUser.contractUsers.${system}.${portableName}.modes == [ "cli" ];
    }
    {
      name = "mkContractUsers: the member set's members are what its `homes` entries bake";
      ok =
        membersFromMember.contractUsers.${system}.${portableName}.identity.name == "Rosa Member"
        && membersFromMember.packages.${system} ? "${portableName}-contractPackage-cli";
    }
    {
      name = "mkContractUsers: a `homes` entry the member set does not hold is a hard bake error";
      ok = !strayEval.success;
    }
    {
      name = "mkContractUser: a member paired with a disagreeing `name` is a hard bake error (index + package name)";
      ok = !mismatchedIndex.success && !mismatchedPackageName.success;
    }
    {
      # …and the positive control for it: the agreeing pair (a member set's own key beside its own
      # member, which is what mkContractUsers always passes) must still bake.
      name = "mkContractUser: a member paired with its own name bakes (the guard is not blanket)";
      ok =
        (mkContractUser {
          inherit pkgs;
          member = portableMember;
          name = portableName;
          homes.cli = syntheticHome portableName;
        }).contractUsers.${system}.${portableName}.identity.name == "Rosa Member";
    }

    # no-IFD, and the gui host-glue fold
    # (g) the plural
    {
      # A users repo holds more people than any one machine wants, which is the whole reason a name
      # is written at all: it SELECTS. Three published, two named, two bound.
      name = "bindContractUsers: binds the users it names, and no others";
      ok =
        (subset.users.users ? ${portableName})
        && (subset.users.users ? mallory)
        && !(subset.users.users ? bo);
    }
    {
      # …and `all` is the case where a host does not have to choose. Note `mallory` is named there
      # too — beside `all`, an entry is not a second selection, it is where that person's settings
      # live.
      name = "bindContractUsers: `all` binds everybody the source publishes";
      ok =
        (everyone.users.users ? ${portableName})
        && (everyone.users.users ? bo)
        && lib.elem "wheel" everyone.users.users.mallory.extraGroups;
    }
    {
      # A per-user `source` reaches somebody the default source has never heard of — so it is an
      # ADDITION beside `all`, not an override of it, and one host can bind across repos.
      name = "bindContractUsers: a per-user source binds somebody the default source does not publish";
      ok = (mixed.users.users ? contractor) && (mixed.users.users ? ${portableName});
    }
    {
      # An entry holds affordances beside a few settings, so a key that is neither would be read as
      # one of them and do nothing. A misspelled feature must not leave an account quietly
      # unpowered.
      name = "bindContractUsers: an entry key that is neither a feature nor a setting is a named error";
      ok = !strayKey.success;
    }
    {
      name = "bindContractUsers: `all` with no source to take everybody from is a named error";
      ok = !allWithoutSource.success;
    }
    {
      name = "bindContractUsers: naming nobody, with `all` unset, is a hard error rather than a host that binds nothing";
      ok = !nobody.success;
    }
    {
      name = "bindContractUsers: a user with no source of its own and no default is a named error";
      ok = !sourceless.success;
    }

    # (h) the key and the identity are one answer
    {
      # The argument a host writes is the INDEX KEY; the account is named by the IDENTITY. Left
      # unguarded these could differ, so an operator writing the index key would create
      # `somebody-else`.
      name = "mkContractUser: publishing under a key that disagrees with the identity is a hard bake error";
      ok = !misnamedBake.success;
    }

    {
      name = "no-IFD: selection reads the index (plain data) and binds against a repo-path fixture";
      ok = selGui.systemd.services ? "contract-activate-${portableName}";
    }
    {
      name = "XDG fold: a granted gui surface links the XDG portal/applications dirs";
      ok =
        let
          p = selGui.environment.pathsToLink;
        in
        lib.elem "/share/xdg-desktop-portal" p && lib.elem "/share/applications" p;
    }
    {
      name = "XDG fold: a cli-only host omits the XDG pathsToLink";
      ok = !(lib.elem "/share/xdg-desktop-portal" selFloor.environment.pathsToLink);
    }
  ];
}
