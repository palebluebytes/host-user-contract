# Conformance fixtures

`reference-contract-package/` and `reference-contract-package-gui/` are `contractPackage`-shaped
directories (an `activate` stub + a `contract-requests.json` sidecar) that stand in for a pinned,
realized `contractPackage` — so `bindContractPackage` reads them as plain repo paths, with no
derivation build and no IFD, exactly as a host reads a pinned flake input.

Their `contract-requests.json` is **not hand-maintained**: it is byte-for-byte the output of the
manifest module's `writeManifest` (issue #27). `reference-contract-package` is a **v1** manifest
(no `granted`, exercising the v1→v2 compat read); `reference-contract-package-gui` is **v2**
(`granted = ["gui"]`, exercising the coupling guard). `conformance/contract-package.nix` asserts
each file equals `writeManifest`'s output for its fields, so the fixtures cannot silently drift from
the schema. To regenerate after a schema change, copy `writeManifest`'s output for the same fields
back into the file (the equivalence assertion tells you when they diverge).
