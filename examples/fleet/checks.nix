# Reference-fleet smoke/coherence checks — the POSITIVE-space counterpart to the
# contract's synthetic conformance suite. Where that suite fabricates adversarial worlds to probe
# the contract's decision logic (the ban FIRES, the clamp DROPS), this proves a realistic,
# correct fleet — the reference user fleet bound on real hosts — evaluates coherently and exhibits
# the contract's promises in the direction a real consumer sees them. It never replaces the
# synthetic suite; it complements it — oracle vs reference.
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
      # ada is afforded NOTHING on desk. She still gets the input groups a graphical session needs,
      # because they ride the MODE she was bound in — which is what makes the machine capability
      # and the per-person policy genuinely different mechanisms rather than one wearing two hats.
      name = "machine capability: ada is a GUI user on desk with an EMPTY affordance set";
      ok = (lib.elem "uinput" (acct "desk" "ada").extraGroups) && cfgs.desk.contract.display.enabled;
    }
    {
      name = "machine capability: the SAME ada is CLI-only on agent — the hardware differs, not the policy";
      ok = !(lib.elem "uinput" (acct "agent" "ada").extraGroups) && !cfgs.agent.contract.display.enabled;
    }
    {
      # MODE SELECTION, from the outside: desk declares gui so it RUNS { cli, gui } and binds
      # ada's gui home; agent declares nothing so it runs { cli } alone and binds her cli home.
      # Neither host says anything about ada — the run set is a fact about the MACHINE — and the
      # same identity, from one source, lands on two different homes.
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
      # PER-USER AFFORDANCES, on ONE host: desk binds three users with three different affordance
      # sets, so what each account holds differs without any second mechanism. ada is afforded
      # nothing, so she gets neither docker nor wheel on the very machine that confers both to
      # somebody else.
      name = "per-user affordances: on ONE host, ada gets neither cleo's docker nor admin's wheel";
      ok =
        let
          g = (acct "desk" "ada").extraGroups;
        in
        lib.elem "uinput" g && !(lib.elem "docker" g) && !(lib.elem "wheel" g);
    }
    {
      # …and the other half of the split: the display surface follows the MACHINE, not its users.
      # desk would need one even with nobody bound, which is precisely what a greeter requires —
      # the surface must exist before the first walk-up user does.
      name = "machine capability: the display surface follows contract.modes, not any account";
      ok = cfgs.desk.contract.display.enabled && !cfgs.vault.contract.display.enabled;
    }
    {
      # The mode's groups reach a cli account on a gui machine? No: they ride the SELECTED mode.
      # svc runs only in a terminal, so on a seat with a display it still gets no input groups.
      name = "mode groups ride the SELECTED mode, not the machine";
      ok = !(lib.elem "uinput" (acct "vault" "svc").extraGroups);
    }
    {
      name = "agent (exposed) evaluates coherently — exposure is a plain host fact, no ban";
      ok = cfgs.agent.contract.exposed && (failing cfgs.agent == [ ]);
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
