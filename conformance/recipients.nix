# Conformance domain: recipient derivation (mkFeatureRecipients, ADR-0001 slice 06). The shipped
# registry declares no `secretFiles` — the one secret-bearing feature, `signing`, rides the USER's
# own home sops decrypted by the user's own key, with no host re-key — so `mkFeatureRecipients` is
# VACUOUS over every real fleet (it returns `{}`), and the recipient-derivation logic had ZERO
# coverage (issue #20). This domain gives it coverage without touching the shipped registry:
#
#   1. It declares a SYNTHETIC secret-bearing feature that DOES carry `secretFiles`, LOCAL to the
#      conformance world (it never edits ./features.nix), and re-instantiates the REAL derivation
#      logic (../lib.nix, a pure function of { lib, registry, featureMeta } per ADR-0004) over it —
#      so the code under test is exactly the code that runs in a fleet.
#   2. It feeds synthetic `nixosConfigurations`-shaped DATA — the exact
#      `config.custom.users.<u>.granted.<f>.enable` path the function reads from a real fleet — with
#      some hosts granting the feature and some not, and asserts the derived recipient set for the
#      feature's secret file equals EXACTLY the granting hosts' keys.
#
# Why data rather than toolkit systems: a synthetic feature has no `granted.<f>` option in the
# shipped contract umbrella, so a real evaluated system could not even express the grant.
# `mkFeatureRecipients` is a pure map over the config shape, so a synthetic host IS that shape as
# data — the same isolation the rest of the suite gets from the umbrella, applied to a function
# whose input is a whole fleet.
{ lib }:
let
  secretFile = "secrets/shared-vault.yaml";

  # The synthetic registry — two secret-bearing features, LOCAL to conformance:
  #   vault : declares `secretFiles` ⇒ its recipients are DERIVED from the hosts that grant it.
  #   token : secret-bearing but declares NO `secretFiles` (like the shipped `signing`) ⇒ it
  #           contributes no file key at all, proving the algorithm keys off `secretFiles`, not
  #           `secretBearing` — a host granting only `token` earns no recipient entry.
  syntheticRegistry = {
    vault = {
      grant = "the shared vault feature (synthetic, conformance-only)";
      secretBearing = true;
      secretFiles = [ secretFile ];
    };
    token = {
      grant = "a host-re-keyless secret feature (synthetic, conformance-only)";
      secretBearing = true;
    };
  };

  # The `featureMeta` projection, derived from the registry EXACTLY as kit.nix derives it (so the
  # test consumes the same shape the fleet does, not a hand-rolled one).
  syntheticFeatureMeta = lib.mapAttrs (
    _: f:
    {
      secretBearing = f.secretBearing or false;
    }
    // lib.optionalAttrs (f ? secretFiles) { inherit (f) secretFiles; }
  ) syntheticRegistry;

  # The REAL derivation logic, re-instantiated over the synthetic registry.
  syntheticLib = import ../lib.nix {
    inherit lib;
    registry = syntheticRegistry;
    featureMeta = syntheticFeatureMeta;
  };

  # Synthetic hosts as data in the shape mkFeatureRecipients reads from a fleet's
  # nixosConfigurations: config.custom.users.<u>.granted.<f>.enable.
  grantOf = features: {
    granted = lib.genAttrs features (_: {
      enable = true;
    });
  };
  mkHost = users: { config.custom.users = users; };
  nixosConfigurations = {
    # desk grants vault (via alice); bob is a co-resident NON-granting user on the same host.
    desk = mkHost {
      alice = grantOf [ "vault" ];
      bob = grantOf [ ];
    };
    # server grants vault (via carol).
    server = mkHost { carol = grantOf [ "vault" ]; };
    # kiosk grants only token (no secretFiles) ⇒ it must contribute NO recipient to the vault file.
    kiosk = mkHost { dave = grantOf [ "token" ]; };
  };

  recipients = syntheticLib.mkFeatureRecipients nixosConfigurations;
  vaultRecipients = recipients.${secretFile} or [ ];
  sorted = xs: lib.sort (a: b: a < b) (lib.unique xs);
in
{
  assertions = [
    {
      name = "recipients: the vault secret file's recipients = EXACTLY the hosts that grant vault";
      ok =
        sorted vaultRecipients == [
          "desk"
          "server"
        ];
    }
    {
      name = "recipients: a host that grants the feature to nobody (kiosk) contributes no recipient";
      ok = !(lib.elem "kiosk" vaultRecipients);
    }
    {
      # desk carries a granting user (alice) AND a co-resident non-granting user (bob): the host must
      # appear because of alice (bob does not suppress it) and appear EXACTLY ONCE (bob, and the
      # `lib.unique` fold, do not duplicate it) — the co-resident isolation the recipient set needs.
      name = "recipients: a co-resident non-granting user (bob) neither suppresses nor duplicates its host";
      ok = lib.count (h: h == "desk") vaultRecipients == 1;
    }
    {
      name = "recipients: a secret-bearing feature with no secretFiles (token) yields no file key";
      ok = lib.attrNames recipients == [ secretFile ];
    }
  ];
}
