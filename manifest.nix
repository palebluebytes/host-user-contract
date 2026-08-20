# The manifest module — the SINGLE owner of the `contract-manifest.json` schema, the seam between
# the producer (`mkContractPackage`) and the consumer (`bindContractUser`). It owns the manifest
# VERSION, its FIELD SET (`version`, `username`, `packages`, `mode`) and the seam FILENAME.
# `writeManifest` serializes a manifest to a store path at EVAL TIME via `builtins.toFile` (pure,
# no IFD); `readManifest` parses a pinned store path back into the canonical field set. The
# producer writes THROUGH `writeManifest` and the consumer reads THROUGH `readManifest`, so neither
# re-encodes the shape independently.
#
# WHAT THE MANIFEST FREEZES is the MODE the home was built for. That is precisely the thing a bind
# cannot change — a grant is conferred on the account at activation and can never reach into a
# sealed home, so there is nothing about a grant worth freezing, while activating a graphical home
# on a machine with no display is a mismatch worth refusing by name.
#
# There is NO backward-compatibility read. A manifest is produced and consumed through this one
# module; a version it does not recognise is a hard, named error rather than a shape guessed at.
{ lib }:
let
  # The current manifest version. `writeManifest` emits it; `readManifest` refuses anything else.
  currentVersion = 4;

  # The seam filename inside a contractPackage — single-sourced so the producer writes and the
  # consumer reads the SAME name.
  fileName = "contract-manifest.json";
in
{
  # The seam filename, exposed so the producer/consumer (and the conformance fixtures) reference
  # this module's value rather than re-spelling it.
  manifestFileName = fileName;

  # The version, exposed for the same reason: a fixture that wants to author a WRONG version must
  # be able to say "not this one" without hardcoding the right one.
  manifestVersion = currentVersion;

  # writeManifest: serialize the manifest field set to a store path at eval time
  # (`builtins.toFile`, no IFD). Returns the JSON file's store path, which the producer copies into
  # the contractPackage under `manifestFileName`.
  writeManifest =
    {
      username,
      packages,
      # The MODE this home was built for — the one thing about a home a bind cannot change, and so
      # the one thing worth freezing. No default: an artifact always belongs to a mode.
      mode,
      version ? currentVersion,
    }:
    builtins.toFile "contract-manifest-${username}.json" (
      builtins.toJSON {
        inherit
          version
          username
          packages
          mode
          ;
      }
    );

  # readManifest: parse a pinned manifest file (`${contractPackage}/${manifestFileName}`, already
  # in the store) into the canonical field set. A plain `importJSON` — the file is pre-built and
  # pinned (a realized store path), so this is not IFD.
  readManifest =
    manifestFile:
    let
      raw = lib.importJSON manifestFile;
    in
    assert lib.assertMsg (raw.version or null == currentVersion)
      "contract: ${fileName} declares version ${
        builtins.toJSON (raw.version or null)
      }, but this contract reads version ${toString currentVersion}. The producer and the host are pinned to different contract revisions; align them.";
    {
      inherit (raw)
        version
        username
        packages
        mode
        ;
    };
}
