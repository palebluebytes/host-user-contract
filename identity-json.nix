# The `identity.json` convention (ADR-0005, issue #5) — the contract owns the path, the
# schema, and a loader for a user's PUBLIC identity, carried as DATA (not Nix). A host or
# greeter reads the same file with `jq` to authenticate BEFORE evaluating any of the user's
# Nix (ADR-0005, data-before-code: eval is not a sandbox), while the user's home module
# loads it with `loadIdentity` so the two can never drift.
#
# The schema is DERIVED from identity.nix — the single identity source — exactly as every
# feature surface is a projection of the registry (kit.nix). So it cannot drift: there is no
# second field list to keep in sync. `loadIdentity` is total over identity.nix (issue #5 schema
# reconciliation: `trustedKeys` is read by realization.nix and so MUST be carriable here, not just
# the fields ADR-0005 names in its sketch of the schema), and an unknown key is a loud error (a
# typo-net), never a silently-dropped field.
#
# THREE PROJECTIONS OF identity.nix LIVE HERE, and they are the whole reason this file exists:
# the SCHEMA (which fields are required), the runtime greeter's FIELD NAMES, and the DEFAULTS
# (what an omitted optional field becomes). The last one used to be the option submodules' job on
# each surface separately; it moved here when both surfaces went `readOnly` and could no longer
# carry defaults at all (modules.nix, ADR-0005).
{ lib, identityOptions }:
let
  # Projected from identity.nix's option set: `required` = its no-default options (the ones
  # that must be present), `optional` = its defaulted ones, `known` = all of them.
  required = lib.attrNames (lib.filterAttrs (_: o: !(o ? default)) identityOptions);
  optional = lib.attrNames (lib.filterAttrs (_: o: o ? default) identityOptions);
  known = lib.attrNames identityOptions;

  # THE ONE RESOLUTION OF THE DEFAULTS (ADR-0005). A partial identity record — anything short of
  # every field identity.nix declares — completed with what identity.nix says an omitted field
  # becomes. Raw wins per field, and it is idempotent, so a record that is already complete passes
  # through untouched.
  #
  # It exists as a FUNCTION rather than as option defaults because NEITHER option surface carries
  # defaults any more: both hold their identity `readOnly` (modules.nix), and the module system
  # counts a declared `default` as a definition, so a defaulted readOnly option could never also be
  # DEFINED (lib/modules.nix throws on more than one). Every holder is therefore handed a record
  # that is already complete, and this is where it gets completed.
  #
  # PROJECTED from identity.nix like `required`/`optional` above — there is no second list of what
  # an omitted field becomes, and a default changed in the single identity source moves this with it.
  resolveIdentity =
    raw: lib.mapAttrs (_: o: o.default) (lib.filterAttrs (_: o: o ? default) identityOptions) // raw;
in
{
  inherit resolveIdentity;

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

  # Parse, validate and RESOLVE an identity.json into a complete identity record — the value
  # assigned to `contract.users.<u>.identity` and to a home's `contract.identity`. Errors loudly on
  # a missing required field or an unknown key, rather than producing a silently-wrong account.
  #
  # It returns a COMPLETE record, not the raw parse: defaulting used to happen in the option
  # submodule, downstream of here and separately on each surface, and once the surfaces went
  # readOnly it could not happen there at all. Parse and resolve are one step for the same reason
  # ADR-0005 gives for one loader — the alternative is two owners of "what a user with no sshKey
  # has", and they are free to disagree.
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
    resolveIdentity raw;
}
