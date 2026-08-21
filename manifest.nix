# The manifest module — the SINGLE owner of the `contract-manifest.json` schema, the seam between
# the producer (`mkContractPackage`) and the consumer (`bindContractUser`). It owns the manifest
# VERSION, its FIELD SET (`version`, `username`, `packages`, `mode`) and the seam FILENAME.
# `writeManifest` serializes a manifest to a store path at EVAL TIME via `builtins.toFile` (pure,
# no IFD); `readManifest` parses a pinned store path back into the canonical field set. The
# producer writes THROUGH `writeManifest` and the consumer reads THROUGH `readManifest`, so neither
# re-encodes the shape independently.
#
# WHAT THE MANIFEST FREEZES is the MODE the home was built for — precisely the thing a bind cannot
# change, and so the thing worth asserting about (ADR-0012). There is NO backward-compatibility
# read: a manifest is produced and consumed through this one module.
#
# THE VERSION IS THE CONTRACT'S ONE VERSION — ./version.nix, the release version release-please
# owns — and compatibility is by MAJOR release rather than exact match, so a package built by an
# older contract keeps binding until one (ADR-0024).
#
# THE DISCIPLINE THIS BUYS AND REQUIRES: changing this file's FIELD SET is a breaking change and
# must be committed as one (`feat!:` or a `BREAKING CHANGE:` footer). That is what moves the
# compatibility line and refuses the packages the change would otherwise mis-read. Add a field
# quietly under `fix:` and old packages will be accepted against a reader that expects it.
# (Stated here on purpose: ADR-0024 puts it at the point of the decision, and this is that point.)
{ lib }:
let
  # The contract's one version, read from the file release-please owns. `writeManifest` stamps it;
  # `readManifest` accepts anything on the same compatibility line. Imported here rather than passed
  # in because this module cannot reach `flake.nix` (a flake's outputs are not an importable
  # expression) and `kit.nix` cannot take a second parameter — the greeter re-imports the kit at
  # login with only `lib` in hand (ADR-0020), so a new parameter would break a seat.
  currentVersion = import ./version.nix;

  # The COMPATIBILITY LINE of a version: its leftmost non-zero component, which is the part a
  # breaking change moves. Two versions are compatible exactly when these are equal. `0.0.x` is
  # deliberately degenerate — every patch is its own line — because pre-0.1 nothing is stable yet.
  lineOf =
    version:
    let
      parts = builtins.splitVersion version;
      at = i: if builtins.length parts > i then builtins.elemAt parts i else "0";
      major = at 0;
      minor = at 1;
    in
    if major != "0" then
      major
    else if minor != "0" then
      "${major}.${minor}"
    else
      "${major}.${minor}.${at 2}";

  # Two versions are compatible exactly when they share a compatibility line.
  compatible = a: b: lineOf a == lineOf b;

  # The seam filename inside a contractPackage — single-sourced so the producer writes and the
  # consumer reads the SAME name.
  fileName = "contract-manifest.json";
in
{
  # The seam filename, exposed so the producer/consumer (and the conformance fixtures) reference
  # this module's value rather than re-spelling it.
  manifestFileName = fileName;

  # THE contract version, exposed so a fixture or a VM can stamp the live value rather than
  # hardcoding a string that changes on every release. Named `contractVersion` and not
  # `manifestVersion` on purpose: it does not version the manifest, it versions the contract — the
  # manifest merely declares it (CONTEXT.md, "the contract version").
  contractVersion = currentVersion;

  # The compatibility predicate, exposed so the conformance suite can prove the RULE against fixed
  # pairs rather than against wherever the repo's version happens to sit today.
  versionsCompatible = compatible;

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
    # Compatible, not identical: a package built by any release on this contract's compatibility
    # line is accepted, so routine releases never invalidate what is already published. A version
    # off the line means a MAJOR release happened between the two sides — the agreement itself
    # changed, and the fields here can no longer be trusted to mean what this reader expects.
    assert lib.assertMsg (raw ? version && compatible raw.version currentVersion)
      "contract: ${fileName} declares version ${
        builtins.toJSON (raw.version or null)
      }, which is not compatible with this contract's version ${builtins.toJSON currentVersion} (compatibility is by major version: ${builtins.toJSON (lineOf currentVersion)}.x). A major release happened between the producer that built this package and the host reading it, so the activation, the account plan and the mode groups may all have moved. Rebuild the package against this host's contract, or pin the host to a release on the package's line — `users.inputs.contract.follows = \"contract\"` keeps them in step by construction.";
    {
      inherit (raw)
        version
        username
        packages
        mode
        ;
    };
}
