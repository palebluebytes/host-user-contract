# The `identity.json` convention (ADR-0023, issue #5) — the contract owns the path, the
# schema, and a loader for a user's PUBLIC identity, carried as DATA (not Nix). A host or
# greeter reads the same file with `jq` to authenticate BEFORE evaluating any of the user's
# Nix (ADR-0022, data-before-code: eval is not a sandbox), while the user's home module
# loads it with `loadIdentity` so the two can never drift.
#
# The schema MIRRORS identity.nix exactly — every field the realization reads — so a user
# materialized purely from `identity.json` loses nothing (issue #5 schema reconciliation:
# `trustedKeys` and `extraGroups` are read by realization.nix and so MUST be carriable
# here, not just the five fields ADR-0023 first named). `loadIdentity` is therefore lossless
# and total over identity.nix: required fields mirror identity.nix's no-default options,
# optional fields mirror its defaulted ones, and an unknown key is a loud error (a typo-net),
# never a silently-dropped field.
{ lib }:
let
  # Mirrors identity.nix: `required` = the options with no default there; `optional` = the
  # defaulted ones. Keep this in lockstep with identity.nix (the one place that can drift).
  required = [
    "name"
    "email"
    "username"
  ];
  optional = [
    "gmail"
    "sshKey"
    "hashedPassword"
    "extraGroups"
    "trustedKeys"
  ];
  known = required ++ optional;
in
{
  # The schema, exposed for introspection (and to document the jq-readable shape a host
  # authenticates against before any eval).
  identitySchema = { inherit required optional; };

  # The conventional filename a user repo ships at its root.
  identityFile = "identity.json";

  # Parse + validate an identity.json into the identity option shape (the attrset assigned
  # to `custom.users.<u>.identity` / the home `identity`). Errors loudly on a missing
  # required field or an unknown key, rather than producing a silently-wrong account; the
  # option submodule fills defaults for any omitted optional field.
  loadIdentity =
    path:
    let
      raw = builtins.fromJSON (builtins.readFile path);
      keys = builtins.attrNames raw;
      missing = lib.subtractLists keys required;
      unknown = lib.subtractLists known keys;
    in
    assert lib.assertMsg
      (
        missing == [ ]
      ) "identity.json (${toString path}) is missing required field(s): ${lib.concatStringsSep ", " missing}";
    assert lib.assertMsg
      (
        unknown == [ ]
      ) "identity.json (${toString path}) has unknown field(s): ${lib.concatStringsSep ", " unknown} — schema is: ${lib.concatStringsSep ", " known}";
    raw;
}
