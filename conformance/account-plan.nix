# accountPlan — the account-combining RULE, proven as a unit with NO boot (issue #31 follow-up).
#
# `accountPlan (identity, grants) → record` is the ONE owner of the four-field rule both adapters
# render: the build-time realization.nix and — since the evaluator landed — the runtime greeter
# `provision` (which execs `contract-account-plan`, re-importing this same function). Because there
# is now a SINGLE source, the rule's own guarantees no longer need a `runNixOSTest` to reconcile two
# spellings: this domain drives `accountPlan` directly and asserts the clamp, the empty-sshKey drop,
# and key ordering as pure `{ name; ok; }` claims. The greeter-provision VM keeps only what genuinely
# needs a boot — that the shell renderer SURFACES this record onto a real account.
{
  lib,
  accountPlan,
}:
let
  # A resolved identity record (all fields present, as the umbrella submodule / the evaluator's
  # identity.nix defaulting produce). Each case overrides only what it exercises.
  base = {
    name = "Test User";
    hashedPassword = "$6$base$hash";
    sshKey = "";
    trustedKeys = [ ];
    extraGroups = [ ];
  };
  plan =
    identity: grants:
    accountPlan {
      identity = base // identity;
      inherit grants;
    };
  has = g: r: lib.elem g r.extraGroups;

  noGrant = { };
  gui = {
    gui.enable = true;
  };
  containers = {
    containers.enable = true;
  };
in
{
  assertions = [
    # The clamp: a privileged group self-declared in identity.extraGroups is dropped when no grant
    # confers it — a user cannot self-escalate. (Same rule realization.nix's clamp assertions prove
    # through a full system eval; here it is the unit under test.)
    {
      name = "account-plan: privileged group (docker) is clamped out without a grant";
      ok =
        !has "docker" (
          plan {
            extraGroups = [
              "audio"
              "docker"
            ];
          } noGrant
        );
    }
    # …while a NON-privileged self-declared group is kept.
    {
      name = "account-plan: non-privileged declared group (audio) is kept";
      ok = has "audio" (
        plan {
          extraGroups = [
            "audio"
            "docker"
          ];
        } noGrant
      );
    }
    # A grant restores the privileged group it confers — privilege enters ONLY via a grant.
    {
      name = "account-plan: the containers grant confers docker";
      ok = has "docker" (plan { extraGroups = [ "docker" ]; } containers);
    }
    # The grant→groups fold: gui confers its input groups.
    {
      name = "account-plan: the gui grant confers its input groups";
      ok = has "input" (plan { } gui) && has "uinput" (plan { } gui);
    }
    # authorizedKeys, empty-sshKey branch: an empty primary key is DROPPED (not written blank),
    # trustedKeys alone remain. This is the branch the greeter-provision VM used to carry a whole
    # second fixture for; it is a property of the rule, so it belongs here.
    {
      name = "account-plan: an empty sshKey drops the primary, keeping trustedKeys";
      ok =
        (plan {
          sshKey = "";
          trustedKeys = [ "k-trust" ];
        } noGrant).authorizedKeys == [ "k-trust" ];
    }
    # …and a non-empty primary precedes trustedKeys, in order.
    {
      name = "account-plan: the primary sshKey precedes trustedKeys, in order";
      ok =
        (plan {
          sshKey = "k-primary";
          trustedKeys = [
            "k-a"
            "k-b"
          ];
        } noGrant).authorizedKeys == [
          "k-primary"
          "k-a"
          "k-b"
        ];
    }
    # The verbatim fields: GECOS ← name, hashedPassword carried through unchanged.
    {
      name = "account-plan: description = identity name, hashedPassword carried verbatim";
      ok =
        let
          r = plan {
            name = "Ada";
            hashedPassword = "$6$secret$hash";
          } noGrant;
        in
        r.description == "Ada" && r.hashedPassword == "$6$secret$hash";
    }
  ];
}
