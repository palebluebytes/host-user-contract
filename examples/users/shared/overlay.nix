# The SHARED OVERLAY of the reference user fleet (ADR-0020, amended 2026-08-15 by issue #36).
#
# One overlay, imported by every user that opts into the shared setup — the overlay half of the
# sharing mechanism ADR-0020 blesses. (Its layout block draws root-level `overlays/`; the amendment
# says the block illustrates an arrangement rather than fixing one, so this fixture keeps the module
# and its overlay together under `shared/`.) It is deliberately trivial: a marker program, so the
# fixture realizes for nearly free while still putting a package from the overlay into each
# opting-in user's CLOSURE. An overlay proof that never reaches a closure proves nothing.
#
# It is IDENTITY-FREE by construction: an overlay runs before any home is evaluated and has no
# `config`, so it cannot key on a user. That is the point of the split — the overlay is the shared
# CODE, `shared/module.nix` is what turns it into per-user DATA (keyed on config.identity.username).
# Because it is identity-free, both duo users get the byte-identical derivation; `shared/module.nix`
# is what diverges. The `shared-code-per-user-data` check asserts exactly that pair of facts.
#
# A home adds this to its own `nixpkgs.overlays`; home-manager's `modules/misc/nixpkgs.nix` rebinds
# `_module.args.pkgs` at priority 100, beating the producer-passed pkgs' mkDefault (1000), so a
# home's own overlays MERGE with the producer's rather than replacing them (probed against this
# repo's pinned home-manager: passing overlay A and declaring overlay B yields both, n = 2).
# It closes over nothing but `prev`, so a home importing it needs no `inputs` specialArg
# (ADR-0020's amendment) — the producer keeps passing `hostFacts` alone.
_: prev: {
  contract-shared-marker = prev.writeShellScriptBin "contract-shared-marker" ''
    echo "contract-shared-marker from examples/users/shared/overlay.nix"
  '';
}
