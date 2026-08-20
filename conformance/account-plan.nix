# accountPlan — the account-combining RULE, proven as a unit with NO boot (issue #31 follow-up).
#
# `accountPlan (identity, grants, mode) → record` is the ONE owner of the account-combining rule
# both adapters render: the build-time realization.nix and the runtime greeter `provision` (which
# execs `contract-account-plan`, re-importing this same function). Because there is a SINGLE
# source, the rule's guarantees need no boot to reconcile two spellings: this domain drives
# `accountPlan` directly. The greeter-provision VM keeps only what genuinely needs one — that the
# shell renderer SURFACES this record onto a real account.
#
# TWO GROUP SOURCES meet here, and the claims below hold them apart: what the host GRANTED (a
# decision about a person) and what the MODE needs (a property of the session shape). There is no
# third — an identity cannot name a group — which is why an ordinary desktop user's account can be
# fully graphical with an empty grant set, and why there is no untrusted group input to filter.
{
  lib,
  floorMode,
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
  };
  # Every case names its mode explicitly; the floor is the default because most claims here are
  # about the other two group sources and a terminal session needs nothing.
  planIn =
    mode: identity: grants:
    accountPlan {
      identity = base // identity;
      inherit grants mode;
    };
  plan = planIn floorMode;
  has = g: r: lib.elem g r.extraGroups;

  noGrant = { };
  containers = {
    containers = true;
  };
in
{
  assertions = [
    # An account afforded nothing, in the floor, holds nothing. There is no identity input to
    # filter out — the rule is that groups only ever come from a grant or a mode.
    {
      name = "account-plan: an account with no grant and no session groups holds none";
      ok = (plan { } noGrant).extraGroups == [ ];
    }
    # Privilege enters ONLY via a grant.
    {
      name = "account-plan: the containers grant confers docker";
      ok = has "docker" (plan { } containers);
    }
    # The MODE→groups fold, and the claim the whole machine/person split rests on: a graphical
    # session's input groups arrive from the SESSION SHAPE, with an entirely empty grant set.
    {
      name = "account-plan: the gui MODE confers its input groups with nothing granted";
      ok =
        let
          r = planIn "gui" { } noGrant;
        in
        has "input" r && has "uinput" r;
    }
    # …and the control: the same identity and the same (empty) grant in the floor gets none of
    # them. The groups follow the session, not the account and not the machine.
    {
      name = "account-plan: the floor confers no session groups (the control)";
      ok = !has "uinput" (plan { } noGrant);
    }
    # The two sources compose without either reaching into the other: a privileged grant beside a
    # graphical session yields both, and neither is a route to the other.
    {
      name = "account-plan: a grant and a mode compose — docker from the grant, uinput from the mode";
      ok =
        let
          r = planIn "gui" { } containers;
        in
        has "docker" r && has "uinput" r;
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
