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
  # WHICH home a host bound, observed the only way a host config shows it: the contractPackage its
  # activation service runs. Two hosts landing on two paths for one user is two different homes —
  # which is the whole of "the mode is selected per host" from the outside.
  boundHome =
    host: user: cfgs.${host}.systemd.services."contract-activate-${user}".serviceConfig.ExecStart;

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
      # MODE SELECTION (ADR-0032), from the outside: desk affords gui so it RUNS { cli, gui } and
      # binds ada's gui home; agent affords nothing so it runs { cli } and binds her cli home.
      # Neither host declares a mode — the run set is derived from the affordances — and the same
      # identity, from one users flake, lands on two different homes.
      name = "mode selection: desk and agent bind DIFFERENT homes of the same ada";
      ok = boundHome "desk" "ada" != boundHome "agent" "ada";
    }
    {
      # …and the non-vacuity of that: two headless hosts both run { cli } alone, so the same user
      # bound on both lands on the SAME home. Without this, "the paths differ" could pass for a
      # reason that has nothing to do with the mode.
      name = "mode selection: two hosts running the same modes bind the SAME home (the control)";
      ok = boundHome "vault" "svc" == boundHome "agent" "svc";
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
      name = "sudo: admin's sudo grant confers wheel and no docker (atomic — docker is the containers grant)";
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
  reference fleet — real hosts × the reference user fleet (bound turnkey via bindContractUser):
  ${report}
  EOF
  ${lib.optionalString (failures != [ ]) ''
    echo "reference fleet checks FAILED (see above)" >&2
    exit 1
  ''}
  touch $out
''
