# The manifest module (issue #27): the SINGLE owner of the `contract-requests.json` schema — the
# seam between the producer (`mkContractPackage`) and the consumer (`bindContractPackage`). It owns
# the manifest VERSION, its FIELD SET (`version`, `username`, `requests`, `packages`, `mode`), the
# seam FILENAME, and the backward-compatibility read. `writeManifest` serializes a manifest to a
# store path at EVAL TIME via `builtins.toFile` (pure, no IFD); `readManifest` parses a pinned store
# path back into the canonical field set. The producer writes THROUGH `writeManifest` and the
# consumer reads THROUGH `readManifest`, so neither re-encodes the shape independently (ADR-0016).
#
# WHAT THE MANIFEST FREEZES is the MODE the home was built for (ADR-0032 §8) — one field, not the
# list of grants v2 carried. That is the direct translation of ADR-0016's coupling guard: a grant
# can no longer change a home, so there is nothing about a grant to freeze, while the mode is
# precisely the thing a bind cannot change and so precisely the thing worth asserting about.
{ lib }:
let
  # The current manifest version. v3 replaced v2's `granted` (the enabled feature names baked into
  # the home) with `mode` (the session shape it was built for) — the ADR-0032 restructuring on the
  # wire. v2 in turn added `granted` to v1's `{ version, username, requests, packages }`.
  # `writeManifest` emits the current version; `readManifest` accepts any of the three (a pre-v3
  # manifest predates `mode`, so it reads back as `null` — see below).
  currentVersion = 3;

  # The wire spelling of the mode field, named once so the write and read sides below cannot drift
  # on it — and so a future version bump that renames it on the wire is one edit.
  modeWireField = "mode";

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
  # no IFD). `version` defaults to the current (v3); passing an older one emits that LEGACY shape —
  # used only to author the compat fixtures and their proofs, never by the live producer (which
  # always bakes the current version). Returns the JSON file's store path, which the producer copies
  # into the contractPackage under `manifestFileName`.
  writeManifest =
    {
      username,
      requests,
      packages,
      # The MODE this home was built for (ADR-0032 §8) — the one thing about a home that a bind
      # cannot change, and so the one thing worth freezing. It lands on the wire under
      # `modeWireField`. No default: an artifact always belongs to a mode, and only the legacy
      # FIXTURES pass `null`, to author a pre-v3 manifest for the compat proof.
      mode,
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
        # The field exists only from v3 on — an older manifest omits it (the read side reads it
        # back as `null`).
        // lib.optionalAttrs (version >= 3) { ${modeWireField} = mode; }
      )
    );

  # readManifest: parse a pinned manifest file (`${contractPackage}/${manifestFileName}`, already in
  # the store) into the canonical field set. Applies the backward-compat read: `mode` (absent before
  # v3) normalizes to `null`, and `packages` (absent in v1) to `[ ]`. A plain `importJSON` — the
  # file is pre-built and pinned (a realized store path), so this is not IFD.
  #
  # A `null` mode is the honest reading of a manifest that predates the field: it says nothing about
  # what it was built for, so the coupling guard has nothing to check rather than something to
  # refuse. That is the same posture v1's absent grant-key took, and it is confined to the same
  # place — a home reached through `bindContractUser` is selected BY mode off the index and can
  # never be pre-v3.
  readManifest =
    manifestFile:
    let
      raw = lib.importJSON manifestFile;
    in
    {
      inherit (raw) version username requests;
      packages = raw.packages or [ ];
      mode = raw.${modeWireField} or null;
    };
}
