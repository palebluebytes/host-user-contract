# Conformance domain: the turnkey host-side bind (ADR-0025, issue #25) — `contract.affordances`,
# `bindContractUser`, the `mkContractUser`/`mkContractUsers` producer coin, the coupling guard, and
# the gui XDG fold. All synthetic:
# no host repo, no home-manager. A binding index is fabricated as PLAIN DATA (variant packages are
# the repo-path fixture `bindContractPackage` already uses, so selection reads the index with NO
# derivation build — the no-IFD property is structural, not asserted by side effect).
{
  lib,
  toolkit,
  loadIdentity,
  bindContractUser,
  mkContractUser,
  mkContractUsers,
  pkgs,
  system,
}:
let
  inherit (toolkit) eval;

  # The repo-path fixture (a plain path, not a derivation) that stands in for a baked variant's
  # package. bindContractPackage reads its contract-requests.json at eval time — no build, no IFD.
  fixturePackage = ./fixtures/reference-contract-package;

  # A synthetic user's on-disk identity path (ADR-0020 layout), reused for the binding index and
  # the account assertions. ada declares no privileged group; a second identity below declares
  # `wheel` to prove the clamp still drops a self-declared privileged group.
  adaIdentity = loadIdentity ../examples/users/users/ada/identity.json;
  # An identity that self-declares the privileged `wheel` group — untrusted input the clamp drops
  # unless a grant confers it (the untrusted-safety case (d)).
  wheelClaimant = adaIdentity // {
    username = "mallory";
    name = "Mallory Claimant";
    extraGroups = [ "wheel" ];
  };

  # Fabricate a binding index exactly as mkContractUsers would emit it — pure data. `granted` is a
  # NAME LIST (the variant's grant-key); `package` is the fixture path. Two variants (base + gui)
  # let us exercise maximal-subset selection without baking anything.
  mkIndex =
    {
      identity,
      offer,
      variants,
    }:
    {
      inherit identity offer;
      variants = map (granted: {
        inherit granted;
        package = fixturePackage;
      }) variants;
    };

  # A usersFlake stand-in: only the `contractUsers.<sys>.<user>` surface bindContractUser reads.
  mkUsersFlake = index: { contractUsers.${system}.ada = index; };

  # Bind a user via the turnkey path against a fabricated flake + a host affordance set.
  bindTurnkey =
    {
      index,
      affordances,
    }:
    eval [
      { contract.affordances = affordances; }
      (bindContractUser {
        usersFlake = mkUsersFlake index;
        username = "ada";
      })
    ];

  # --- (a) affordances ∩ offer grant derivation, incl. the host veto ---
  # ada offers gui + sudo; the host affords gui only ⇒ grant = { gui }. sudo is offered but not
  # afforded, so the host's veto drops it.
  adaGuiSudoOffer = mkIndex {
    identity = adaIdentity;
    offer = {
      gui.enable = true;
      sudo.enable = true;
    };
    variants = [
      [ ] # base
    ];
  };
  vetoBind = bindTurnkey {
    index = adaGuiSudoOffer;
    affordances = {
      gui.enable = true;
    };
  };
  vetoGrant = vetoBind.custom.users.ada.granted;

  # --- (b) maximal-subset variant selection incl. the hard-error case ---
  # A user with base + gui variants. Grant { gui, sudo } ⇒ selects gui (sudo rides the bind);
  # grant { sudo } ⇒ selects base (gui not covered). The selected package is the fixture path,
  # so we assert selection SUCCEEDS (the account materializes) rather than inspecting the path.
  twoVariants =
    offer:
    mkIndex {
      identity = adaIdentity;
      inherit offer;
      variants = [
        [ ] # base
        [ "gui" ] # gui
      ];
    };
  selGui = bindTurnkey {
    index = twoVariants {
      gui.enable = true;
      sudo.enable = true;
    };
    affordances = {
      gui.enable = true;
      sudo.enable = true;
    };
  };
  selBase = bindTurnkey {
    index = twoVariants {
      sudo.enable = true;
    };
    affordances = {
      sudo.enable = true;
    };
  };

  # The hard-error case: two incomparable baked variants ([gui] and [sudo]) both ⊆ the derived
  # grant { gui, sudo }, and the combo [gui, sudo] was never baked ⇒ no unique maximum ⇒ throw.
  incomparableIndex = mkIndex {
    identity = adaIdentity;
    offer = {
      gui.enable = true;
      sudo.enable = true;
    };
    variants = [
      [ "gui" ]
      [ "sudo" ]
    ];
  };
  incomparableEval = builtins.tryEval (
    (bindTurnkey {
      index = incomparableIndex;
      affordances = {
        gui.enable = true;
        sudo.enable = true;
      };
    }).custom.users.ada.granted
  );

  # --- (c) the coupling guard: accept ⊆, reject ⊄ ---
  # The fixture is a v1 manifest (no baked `granted`) ⇒ manifest.granted = [ ] ⊆ any grant, so the
  # turnkey binds above already exercise ACCEPT. To exercise REJECT we drive the primitive with a
  # variant whose grant-key is NOT granted — modelled by selecting a baked-[gui] variant while the
  # host affords/derives nothing. Selection would pick base if it existed; with ONLY a [gui]
  # variant and an empty grant, [gui] is not covered ⇒ selection itself errors first. The guard's
  # own accept/reject is proven directly against bindContractPackage in ./contract-package.nix's
  # sibling world; here we assert the turnkey path never lets an uncovered variant through.
  onlyGuiIndex = mkIndex {
    identity = adaIdentity;
    offer = {
      gui.enable = true;
    };
    variants = [
      [ "gui" ]
    ];
  };
  uncoveredEval = builtins.tryEval (
    (bindTurnkey {
      index = onlyGuiIndex;
      affordances = { }; # affords nothing ⇒ grant = { } ⇒ [gui] uncovered
    }).custom.users.ada.granted
  );

  # --- (d) untrusted safety: a privileged offer under a safe-set affordance ---
  # mallory offers sudo and self-declares `wheel` in identity. The host affords only gui (the safe
  # set's shape). grant = { } for sudo ⇒ wheel is never conferred AND the clamp drops the
  # self-declared wheel. The account must have NO wheel.
  malloryIndex = mkIndex {
    identity = wheelClaimant;
    offer = {
      sudo.enable = true;
    };
    variants = [
      [ ]
    ];
  };
  malloryBind = eval [
    {
      contract.affordances = {
        gui.enable = true;
      };
    }
    (bindContractUser {
      usersFlake = {
        contractUsers.${system}.mallory = malloryIndex;
      };
      username = "mallory";
    })
  ];

  # --- (e) mkContractUsers: the emitted shape + no-IFD selection ---
  # A synthetic already-evaluated home (attribute paths mirror a homeManagerConfiguration result),
  # exactly as ./contract-package.nix stands one in for mkContractPackageForHome. One base variant.
  activationStub = pkgs.runCommand "turnkey-activation-stub" { } ''
    mkdir -p $out
    printf '#!/bin/sh\necho activated\n' > $out/activate
    chmod +x $out/activate
  '';
  syntheticHome = {
    activationPackage = activationStub;
    config = {
      contract.requests = {
        gui.desktop = "plasma";
      };
      home = {
        packages = [ pkgs.hello ];
        username = "ada";
      };
    };
  };
  adaOffer = {
    gui.enable = true;
  };
  adaVariants = [
    {
      grants = { };
      home = syntheticHome;
    }
  ];
  bindings = mkContractUsers {
    inherit pkgs;
    inherit system;
    usersDir = ../examples/users/users;
    users.ada = {
      offer = adaOffer;
      variants = adaVariants;
    };
  };
  emittedIndex = bindings.contractUsers.${system}.ada;
  # The SINGULAR partner: mkContractUser bakes ONE user and must emit byte-identical outputs to the
  # roster form for that user (mkContractUsers is nothing but this mapped over the roster).
  singleUser = mkContractUser {
    inherit pkgs system;
    usersDir = ../examples/users/users;
    name = "ada";
    offer = adaOffer;
    variants = adaVariants;
  };
in
{
  assertions = [
    # (a) affordances ∩ offer, with the host veto
    {
      name = "affordances ∩ offer: gui is granted (offered ∧ afforded)";
      ok = vetoGrant.gui.enable;
    }
    {
      name = "host veto: sudo is offered but not afforded ⇒ not granted (absolute veto)";
      ok = !(vetoGrant.sudo.enable or false);
    }

    # (b) maximal-subset selection
    {
      name = "variant selection: grant {gui,sudo} over {base,gui} selects gui (account materializes)";
      ok = selGui.users.users.ada.isNormalUser && selGui.custom.gui.surface.enabled;
    }
    {
      name = "variant selection: grant {sudo} over {base,gui} selects base (no gui surface)";
      ok = selBase.users.users.ada.isNormalUser && !selBase.custom.gui.surface.enabled;
    }
    {
      name = "variant selection: incomparable covers (gui|sudo, combo never baked) is a hard error";
      ok = !incomparableEval.success;
    }

    # (c) coupling guard / turnkey never binds an uncovered variant
    {
      name = "coupling guard: v1 manifest (granted=[]) ⊆ any grant ⇒ accept (turnkey binds ok)";
      ok = vetoBind.users.users.ada.isNormalUser;
    }
    {
      name = "turnkey: an uncovered [gui]-only variant under an empty grant is a hard error";
      ok = !uncoveredEval.success;
    }

    # (d) untrusted safety
    {
      name = "untrusted safety: a privileged offer under a safe (gui-only) affordance confers no wheel";
      ok = !(lib.elem "wheel" malloryBind.users.users.mallory.extraGroups);
    }
    {
      name = "untrusted safety: sudo offered-but-unafforded is not granted (grant is empty)";
      ok = !(malloryBind.custom.users.mallory.granted.sudo.enable or false);
    }

    # (e) mkContractUsers shape + no-IFD selection
    {
      name = "mkContractUsers: emits the named package <user>-contractPackage-base";
      ok = bindings.packages.${system} ? "ada-contractPackage-base";
    }
    {
      name = "mkContractUsers: the binding index carries { identity; offer; variants }";
      ok =
        (emittedIndex ? identity)
        && (emittedIndex ? offer)
        && (emittedIndex ? variants)
        && emittedIndex.identity.username == "ada";
    }
    {
      name = "mkContractUsers: the index variant carries its grant-key names + package";
      ok =
        let
          v = lib.head emittedIndex.variants;
        in
        v.granted == [ ] && (v.package ? outPath);
    }
    {
      name = "no-IFD: selection reads the index (plain data) and binds against a repo-path fixture";
      ok = vetoBind.systemd.services ? "contract-activate-ada";
    }
    {
      # The singular producer is the true per-user partner of bindContractUser: its one-user output
      # must match the roster form for that user (same package store path, same index entry).
      name = "mkContractUser: the singular producer matches mkContractUsers for one user";
      ok =
        (
          singleUser.packages.${system}."ada-contractPackage-base".outPath
          == bindings.packages.${system}."ada-contractPackage-base".outPath
        )
        && singleUser.contractUsers.${system}.ada.identity.username == "ada"
        && singleUser.contractUsers.${system}.ada.offer.gui.enable;
    }

    # gui XDG fold
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
      ok = !(lib.elem "/share/xdg-desktop-portal" selBase.environment.pathsToLink);
    }
  ];
}
