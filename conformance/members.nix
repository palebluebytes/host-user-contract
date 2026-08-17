# Conformance domain: the MEMBER-SET derivation (issue #57) — `mkMembers`, the contract's one
# answer to "who is in this users repo, and what is each identity". Package-free: it is a plain
# `readDir` over a repo path plus the contract's own `loadIdentity`, so every claim here is over
# eval-time data with no build.
#
# The subject is the ADR-0020 layout rule (`users/<u>/identity.json`) — stated ONCE, here, rather
# than re-typed by every producer's own directory scan. So the claims are: what counts as a member,
# what each member carries, and what a directory that holds no member does.
{
  lib,
  loadIdentity,
  mkMembers,
}:
let
  # The synthetic users directory (./fixtures/members) holds all three kinds of entry a real one
  # can: a member, a directory without an identity.json, and a non-directory file. See its README.
  fixtureDir = ./fixtures/members;
  members = mkMembers { usersDir = fixtureDir; };

  # The fixture's own contents, read the same way the derivation does — so the exclusion claims
  # below cannot pass VACUOUSLY (a fixture that lost its half-added directory, or its README, would
  # otherwise prove the filter by having nothing to filter).
  fixtureEntries = builtins.readDir fixtureDir;

  # A memberless directory: `half-added` holds a home.nix and nothing else, so pointing the
  # derivation AT it yields no member. That is the "wrong path" mistake (a `usersDir` off by one
  # level, or renamed), and it must be a named error rather than an empty members that bakes nothing.
  memberless = builtins.tryEval (mkMembers {
    usersDir = ./fixtures/members/half-added;
  });

  # The REAL reference fleet (ADR-0022: the synthetic suite borrows real atoms from the positive-
  # space example, never the reverse) — the derivation must work over the layout a consumer
  # actually ships, not only over the fixture shaped for it.
  realMembers = mkMembers { usersDir = ../examples/users/users; };
in
{
  assertions = [
    {
      name = "members: a directory with an identity.json is a member, keyed by its directory name";
      ok = lib.attrNames members == [ "pip" ];
    }
    {
      name = "members: a member carries its name, its directory, and its resolved identity";
      ok =
        let
          m = members.pip;
        in
        m.name == "pip" && m.dir == ./fixtures/members/pip && m.identity.username == "pip";
    }
    {
      # The identity is the LOADER's own value (ADR-0009: the contract is the single identity
      # loader), not a re-parse: a member is what downstream reads instead of resolving a path.
      name = "members: the member's identity is loadIdentity's value for its identity.json";
      ok = members.pip.identity == loadIdentity ./fixtures/members/pip/identity.json;
    }
    {
      # Non-vacuity for the two exclusions: the fixture really does contain both kinds of entry.
      name = "members: the fixture contains a half-added directory and a non-directory entry";
      ok = fixtureEntries.half-added == "directory" && fixtureEntries."README.md" != "directory";
    }
    {
      name = "members: a directory without an identity.json is not a member";
      ok = !(members ? half-added);
    }
    {
      name = "members: a non-directory entry at the root is not a member";
      ok = !(members ? "README.md");
    }
    {
      name = "members: a directory holding no member at all is a hard error, not an empty members";
      ok = !memberless.success;
    }
    {
      name = "members: derives the reference fleet's own members from the ADR-0020 layout";
      ok =
        (realMembers ? ada)
        && realMembers.ada.dir == ../examples/users/users/ada
        && realMembers.ada.identity.username == "ada"
        && lib.length (lib.attrNames realMembers) > 1;
    }
  ];
}
