# Conformance fixtures

`members/` is a synthetic users directory for the member-set derivation — a member, a half-added
directory, and a non-directory entry. It has its own README.

`reference-contract-package/` and `reference-contract-package-gui/` are `contractPackage`-shaped
directories (an `activate` stub + a `contract-manifest.json` sidecar) that stand in for a pinned,
realized `contractPackage` — so `bindContractPackage` reads them as plain repo paths, with no
derivation build and no IFD, exactly as a host reads a pinned flake input.

Their `contract-manifest.json` is **not hand-maintained**: it is byte-for-byte the output of the
manifest module's `writeManifest`. The two differ only in the frozen `mode` (`cli` and `gui`),
which is what lets `conformance/contract-package.nix` prove the mode coupling guard with a control
— the same host accepts one and refuses the other. That domain asserts each file equals
`writeManifest`'s output for its fields, so the fixtures cannot silently drift from the schema. To
regenerate after a schema change, copy `writeManifest`'s output for the same fields back into the
file (the equivalence assertion tells you when they diverge).

`private-repo-identity.json` is an identity carrying a `$6$` sha512crypt hash — legal under the
private-repo credential posture, and therefore the offender a `require = "yescrypt"` check must
reject.
