# The `identity.json` convention (ADR-0005, issue #5) — the contract owns the path, the
# schema, and a loader for a user's PUBLIC identity, carried as DATA (not Nix). A host or
# greeter reads the same file with `jq` to authenticate BEFORE evaluating any of the user's
# Nix (ADR-0005, data-before-code: eval is not a sandbox), while the user's home module
# loads it with `loadIdentity` so the two can never drift.
#
# The schema is DERIVED from identity.nix — the single identity source — exactly as every
# feature surface is a projection of the registry (kit.nix). So it cannot drift: there is no
# second field list to keep in sync. `loadIdentity` is lossless and total over identity.nix
# (issue #5 schema reconciliation: `trustedKeys` is read by realization.nix and so MUST be
# carriable here, not just the fields ADR-0005 names in its sketch of the schema), and an
# unknown key is a loud error (a typo-net), never a silently-dropped field.
{ lib, identityOptions }:
let
  # Projected from identity.nix's option set: `required` = its no-default options (the ones
  # that must be present), `optional` = its defaulted ones, `known` = all of them.
  required = lib.attrNames (lib.filterAttrs (_: o: !(o ? default)) identityOptions);
  optional = lib.attrNames (lib.filterAttrs (_: o: o ? default) identityOptions);
  known = lib.attrNames identityOptions;
in
{
  # The schema, exposed for introspection (and to document the jq-readable shape a host
  # authenticates against before any eval).
  identitySchema = { inherit required optional; };

  # The identity field NAMES the eval-free runtime greeter reads out of identity.json — the
  # username + credential `auth` verifies and the account fields `provision` realizes through the
  # rendered accountPlan (issue #31). PROJECTED from identity.nix (each name asserted to be a real
  # option) so the shell helpers never carry an independently-hardcoded field list: a rename in the
  # single identity source is a loud build error here, not a silently-stale `jq` path. The name maps
  # to itself (the jq key IS the option name) — the projection's job is the validation, not a rename.
  identityFields =
    let
      names = [
        "username"
        "name"
        "hashedPassword"
        "sshKey"
        "trustedKeys"
      ];
      unknown = lib.subtractLists known names;
    in
    assert lib.assertMsg (unknown == [ ])
      "identity-json: field(s) the runtime greeter reads are not options in identity.nix: ${lib.concatStringsSep ", " unknown}";
    lib.genAttrs names (n: n);

  # The conventional filename a user repo ships at its root.
  identityFile = "identity.json";

  # A raw identity record with identity.nix's own DEFAULTS filled in. `loadIdentity` is lossless
  # over identity.json and leaves an omitted optional field absent, so somebody has to fill it —
  # the host surface has its option submodule do it, and the HOME surface cannot, because its
  # options are `readOnly` and the module system counts a declared `default` as a definition
  # (lib/modules.nix: a defaulted readOnly option can never also be defined). So the home is handed
  # a record that is already complete.
  #
  # PROJECTED from identity.nix like `required`/`optional` above — there is no second list of what
  # an omitted field becomes, and a default changed in the single identity source moves this with
  # it. Raw wins over the default, per field.
  resolveIdentity =
    raw: lib.mapAttrs (_: o: o.default) (lib.filterAttrs (_: o: o ? default) identityOptions) // raw;

  # Parse + validate an identity.json into the identity option shape (the attrset assigned
  # to `contract.users.<u>.identity` / the home `identity`). Errors loudly on a missing
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
    assert lib.assertMsg (missing == [ ])
      "identity.json (${toString path}) is missing required field(s): ${lib.concatStringsSep ", " missing}";
    assert lib.assertMsg (unknown == [ ])
      "identity.json (${toString path}) has unknown field(s): ${lib.concatStringsSep ", " unknown} — schema is: ${lib.concatStringsSep ", " known}";
    raw;
}
