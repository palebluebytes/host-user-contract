# Reference-fleet smoke/coherence checks (docs/adr/0022) — the POSITIVE-space counterpart to the
# contract's synthetic conformance suite. Where that suite fabricates adversarial worlds to probe
# the contract's decision logic (the ban FIRES, the clamp DROPS), this proves a realistic,
# correct fleet — the reference user fleet bound on real hosts — evaluates coherently and exhibits
# the contract's promises in the direction a real consumer sees them. It never replaces the
# synthetic suite; it complements it (ADR-0022: oracle vs reference).
{
  lib,
  pkgs,
  nixosConfigurations,
  mkFeatureRecipients,
}:
let
  cfgs = lib.mapAttrs (_: c: c.config) nixosConfigurations;
  acct = host: user: cfgs.${host}.users.users.${user};
  failing = c: builtins.filter (a: !a.assertion) c.assertions;

  # mkFeatureRecipients over the REAL multi-host fleet — the fleet-only contract function the
  # synthetic suite (single systems) cannot exercise. Vacuous under the current registry: no
  # feature declares `secretFiles` (signing rides the user's own home sops, no host recipients),
  # so the correct result is the empty map. The value here is proving the function runs over a
  # genuine `nixosConfigurations` without error — it lights up the moment a secretFiles-bearing
  # feature is added.
  recipients = mkFeatureRecipients nixosConfigurations;

  assertions = [
    {
      name = "fleet-eval: every host evaluates with no failing assertion";
      ok = lib.all (c: failing c == [ ]) (lib.attrValues cfgs);
    }
    {
      name = "fleet-eval: every bound account realizes as a normal user";
      ok = lib.all (x: x) [
        (acct "workstation" "ada").isNormalUser
        (acct "workstation" "cleo").isNormalUser
        (acct "vault" "ben").isNormalUser
        (acct "vault" "svc").isNormalUser
        (acct "agent" "ada").isNormalUser
        (acct "agent" "svc").isNormalUser
      ];
    }
    {
      name = "grant-divergence: ada is a GUI user on workstation (uinput group + display surface)";
      ok =
        (lib.elem "uinput" (acct "workstation" "ada").extraGroups)
        && cfgs.workstation.custom.gui.surface.enabled;
    }
    {
      name = "grant-divergence: the SAME ada output is CLI-only on agent (no uinput, no surface) — silent degradation";
      ok =
        !(lib.elem "uinput" (acct "agent" "ada").extraGroups) && !cfgs.agent.custom.gui.surface.enabled;
    }
    {
      name = "clamp: cleo receives the privileged 'docker' group ONLY via the workstation grant";
      ok = lib.elem "docker" (acct "workstation" "cleo").extraGroups;
    }
    {
      name = "sudo: admin gets wheel and NOTHING more (the minimal grant — no docker, unlike workstation)";
      ok =
        let
          g = (acct "workstation" "admin").extraGroups;
        in
        (acct "workstation" "admin").isNormalUser && lib.elem "wheel" g && !(lib.elem "docker" g);
    }
    {
      name = "grant: ben is granted signing on the non-exposed vault (baked variant matches, ADR-0016)";
      ok = (acct "vault" "ben").isNormalUser && cfgs.vault.custom.users.ben.granted.signing.enable;
    }
    {
      name = "exposed-host ban: agent is exposed yet grants no secret-bearing feature — no ban failure";
      ok = cfgs.agent.custom.host.exposed && (failing cfgs.agent == [ ]);
    }
    {
      name = "recipients: mkFeatureRecipients evaluates over the real fleet (vacuous — no feature declares secretFiles)";
      ok = recipients == { };
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;
  report = lib.concatMapStringsSep "\n" (
    a: "  ${if a.ok then "ok  " else "FAIL"}  ${a.name}"
  ) assertions;
in
pkgs.runCommand "reference-fleet-checks" { } ''
  cat <<'EOF'
  reference fleet — real hosts × the reference user fleet (bound via bindContractPackage):
  ${report}
  EOF
  ${lib.optionalString (failures != [ ]) ''
    echo "reference fleet checks FAILED (see above)" >&2
    exit 1
  ''}
  touch $out
''
