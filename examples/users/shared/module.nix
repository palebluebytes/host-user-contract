# The SHARED HOME MODULE of the reference user fleet (ADR-0014, amended 2026-08-15 by issue #36).
#
# ADR-0014's central ergonomic is "shared code, per-user data": ONE module, imported by several of
# the operator's own accounts, keyed on `config.identity.username` so no user's identity is ever
# baked into the shared code. Since issue #36 that is PERMITTED, not required — which is exactly why
# it needs a worked example: an optional shape with no exercise rots. duo-a and duo-b import this
# module (and `shared/overlay.nix`); the other five reference users deliberately do not, so the
# members shows both supported arrangements side by side. See ADR-0022's exception note.
#
# Unlike the other five reference homes this module is NOT contract-pure (ADR-0002): it sets
# home-manager's own `home.packages`/`home.file` and reads `pkgs`, so it needs home-manager to
# evaluate. That is fine HERE — this flake has home-manager — but it is precisely why the shared
# pair is kept off ada: the conformance tracer borrows ada's home.nix and evaluates it headlessly
# against the bare contract umbrella, with no home-manager and no nixpkgs (docs/adr/0022).
#
# `contract-shared-marker` comes from `shared/overlay.nix`, which each opting-in user adds to its
# own `nixpkgs.overlays` — so this module's `pkgs` reference is what carries an overlay package into
# the user's closure.
{ config, pkgs, ... }:
let
  # The ONE key. Every per-user divergence below is a function of this and nothing else; there is no
  # `if username == "duo-a"` branch anywhere, and no user's identity is written into this file.
  inherit (config.identity) username;
in
{
  # Shared code, IDENTICAL for every user that imports it: the same store path lands in both
  # closures. This is the half that must NOT vary.
  home.packages = [ pkgs.contract-shared-marker ];

  # Per-user data, DERIVED from the identity the binding injected (ADR-0005). Both the derivation
  # NAME and its content are keyed on the username, so the two homes produce two different store
  # paths and neither carries a trace of the other's identity.
  home.file.".contract-shared-card".source = pkgs.writeText "contract-shared-card-${username}" ''
    # Rendered by examples/users/shared/module.nix — one module, one identity each.
    username=${username}
    name=${config.identity.name}
    email=${config.identity.email}
  '';
}
