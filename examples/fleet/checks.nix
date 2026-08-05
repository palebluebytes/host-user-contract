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
}:
let
  cfgs = lib.mapAttrs (_: c: c.config) nixosConfigurations;
  acct = host: user: cfgs.${host}.users.users.${user};
  failing = c: builtins.filter (a: !a.assertion) c.assertions;

  assertions = [
    {
      name = "fleet-eval: every host evaluates with no failing assertion";
      ok = lib.all (c: failing c == [ ]) (lib.attrValues cfgs);
    }
    {
      name = "fleet-eval: every bound account realizes as a normal user";
      ok = lib.all (x: x) [
        (acct "desk" "ada").isNormalUser
        (acct "desk" "cleo").isNormalUser
        (acct "vault" "ben").isNormalUser
        (acct "vault" "svc").isNormalUser
        (acct "agent" "ada").isNormalUser
        (acct "agent" "svc").isNormalUser
      ];
    }
    {
      name = "grant-divergence: ada is a GUI user on desk (uinput group + display surface)";
      ok = (lib.elem "uinput" (acct "desk" "ada").extraGroups) && cfgs.desk.custom.gui.surface.enabled;
    }
    {
      name = "grant-divergence: the SAME ada output is CLI-only on agent (no uinput, no surface) — silent degradation";
      ok =
        !(lib.elem "uinput" (acct "agent" "ada").extraGroups) && !cfgs.agent.custom.gui.surface.enabled;
    }
    {
      name = "clamp: cleo receives the privileged 'docker' group ONLY via the containers grant";
      ok = lib.elem "docker" (acct "desk" "cleo").extraGroups;
    }
    {
      name = "atomic grants: cleo's containers grant confers docker but NOT wheel (no wheel without sudo)";
      ok =
        let
          g = (acct "desk" "cleo").extraGroups;
        in
        lib.elem "docker" g && !(lib.elem "wheel" g);
    }
    {
      name = "sudo: admin gets wheel and NOTHING more (the minimal grant — no docker, that is the containers grant)";
      ok =
        let
          g = (acct "desk" "admin").extraGroups;
        in
        (acct "desk" "admin").isNormalUser && lib.elem "wheel" g && !(lib.elem "docker" g);
    }
    {
      name = "agent (exposed) evaluates coherently — exposure is a plain host fact, no ban";
      ok = cfgs.agent.custom.host.exposed && (failing cfgs.agent == [ ]);
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;
  report = lib.concatMapStringsSep "\n" (
    a: "  ${if a.ok then "ok  " else "FAIL"}  ${a.name}"
  ) assertions;
in
pkgs.runCommand "reference-fleet-checks" { } ''
  cat <<'EOF'
  reference fleet — real hosts × the reference user fleet (bound turnkey via bindUserFromFlake):
  ${report}
  EOF
  ${lib.optionalString (failures != [ ]) ''
    echo "reference fleet checks FAILED (see above)" >&2
    exit 1
  ''}
  touch $out
''
