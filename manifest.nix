# The manifest module (issue #27): the SINGLE owner of the `contract-requests.json` schema — the
# seam between the producer (`mkContractPackage`) and the consumer (`bindContractPackage`). It owns
# the manifest VERSION, its FIELD SET (`version`, `username`, `requests`, `packages`, `granted`),
# the seam FILENAME, and the v1→v2 compatibility read. `writeManifest` serializes a manifest to a
# store path at EVAL TIME via `builtins.toFile` (pure, no IFD); `readManifest` parses a pinned store
# path back into the canonical field set. The producer writes THROUGH `writeManifest` and the
# consumer reads THROUGH `readManifest`, so neither re-encodes the shape independently (ADR-0016).
#
# THE WIRE NAME AND THE NIX NAME DIFFER, deliberately (ADR-0030). On the wire the coupling-guard
# field is `granted`, because that is what v2 shipped and a JSON key is a format commitment. In Nix
# it is `grantKey` on BOTH sides of this module — the argument `writeManifest` takes and the field
# `readManifest` returns — because the value is a sorted NAME LIST, and `granted` everywhere else in
# this repo means an attrset-shaped option path. This module is therefore the one place the two
# spellings meet, which is exactly what a schema owner is for: the translation lives here, once,
# instead of every reader having to remember that this particular `granted` is not like the others.
{ lib }:
let
  # The current manifest version. v2 added the wire field `granted` (the enabled feature names baked
  # into the home — the ADR-0016 coupling-guard field, surfaced in Nix as `grantKey`) to v1's
  # `{ version, username, requests, packages }`. `writeManifest` emits this by default;
  # `readManifest` accepts EITHER (a v1 manifest predates the field, so it reads back as `[ ]` — the
  # v1→v2 compat).
  currentVersion = 2;

  # The wire spelling of the coupling-guard field, named once so the write and read sides below
  # cannot drift on it — and so a future version bump that renames it on the wire is one edit.
  grantKeyWireField = "granted";

  # The seam filename inside a contractPackage — single-sourced so the producer writes and the
  # consumer reads the SAME name (`mkContractPackage` copies to it; `bindContractPackage` reads it).
  fileName = "contract-requests.json";
in
{
  # The seam filename, exposed so the producer/consumer (and the conformance fixtures) reference the
  # module's value rather than re-spelling it. The version is owned internally via `currentVersion`
  # (the `writeManifest` default) — no consumer needs it as a value, so it is not part of the surface.
  manifestFileName = fileName;

  # writeManifest: serialize the manifest field set to a store path at eval time (`builtins.toFile`,
  # no IFD). `version` defaults to the current (v2); passing `version = 1` emits the LEGACY shape
  # (no `granted`) — used only to author the v1 fixture and the v1→v2 compat proof, never by the
  # live producer (which always bakes the current version). Returns the JSON file's store path,
  # which the producer copies into the contractPackage under `manifestFileName`.
  writeManifest =
    {
      username,
      requests,
      packages,
      # The bake's GRANT-KEY (sorted enabled feature names). Named for what it is; it lands
      # on the wire under `grantKeyWireField` — see the header.
      grantKey ? [ ],
      version ? currentVersion,
    }:
    builtins.toFile "contract-requests-${username}.json" (
      builtins.toJSON (
        {
          inherit
            version
            username
            requests
            packages
            ;
        }
        # The field exists only from v2 on — a v1 manifest omits it (the read side defaults it to []).
        // lib.optionalAttrs (version >= 2) { ${grantKeyWireField} = grantKey; }
      )
    );

  # readManifest: parse a pinned manifest file (`${contractPackage}/${manifestFileName}`, already in
  # the store) into the canonical field set. Applies the v1→v2 compat read: the grant-key field
  # (absent in v1) normalizes to `[ ]`, and `packages` (defensively) too. A plain `importJSON` — the
  # file is pre-built and pinned (a realized store path), so this is not IFD.
  #
  # The wire field is translated to `grantKey` here, so every reader downstream holds a name that
  # says "sorted list", not one that reads like the attrset-shaped `granted` option paths.
  readManifest =
    manifestFile:
    let
      raw = lib.importJSON manifestFile;
    in
    {
      inherit (raw) version username requests;
      packages = raw.packages or [ ];
      grantKey = raw.${grantKeyWireField} or [ ];
    };
}
