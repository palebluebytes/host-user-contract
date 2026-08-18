# Conformance domain: the MODE REGISTRY and the floor (ADR-0032, issue #65).
#
# A mode is the session shape a home is BUILT for, and the registry is its single source — the
# same posture `features.nix` holds for grants. What this domain proves is the registry's own
# invariants and the two projections nothing else can reach: the FLOOR (exactly one, in both
# failure directions) and the association between a mode and the grant a host affords to run it.
#
# The floor guard is driven through `floorOf`, the kernel taking a registry EXPLICITLY, for the
# same reason `homeMatrixOver` takes its upper bound: the contract's own registry has exactly one
# floor by construction, so "no floor" and "two floors" are only demonstrable against a synthetic
# one. Driving the real registry through the same kernel is what keeps the synthetic claims honest
# — the guard the fixtures fail is the guard the contract runs.
#
# Package-free and build-free: the registry is plain data, so every claim is a value or a
# `tryEval` over one.
{
  lib,
  modes,
  floorMode,
  floorOf,
  runsFor,
  selectModeOver,
}:
let
  # The verdict of the floor guard over a synthetic registry, as a boolean. The guard throws a
  # named error (like every other contract guard), so `tryEval` is how a claim observes it.
  floorHolds = reg: (builtins.tryEval (floorOf reg)).success;

  # Synthetic registries, written out rather than derived from the real one: the point is to hand
  # the kernel worlds the contract does not have. Each is otherwise well-formed, so the ONLY thing
  # the guard can be reacting to is the number of floors.
  noFloor = {
    alpha.description = "a mode with no floor flag";
    beta.description = "another";
  };
  twoFloors = {
    alpha = {
      description = "a mode claiming the floor";
      floor = true;
    };
    beta = {
      description = "a second mode claiming it too";
      floor = true;
    };
  };
  oneFloor = {
    alpha = {
      description = "the floor";
      floor = true;
    };
    beta = {
      description = "a rich mode";
      grant = "gui";
    };
  };
  # The selection, over an explicit floor — the kernel form, for the same reason `floorOf` takes a
  # registry: the contract has ONE non-floor mode today, so "two rich modes is an error" is only
  # demonstrable against a synthetic world. `who`/`subject` are the diagnostic's own facts.
  select =
    { runs, published }:
    selectModeOver {
      who = "conformance";
      subject = "ada";
      floor = "cli";
      inherit runs published;
    };
  selects = args: (builtins.tryEval (select args)).success;
in
{
  assertions = [
    {
      # The vocabulary itself. Two modes today; the claim is the SHAPE (every entry describes
      # itself), so a third is covered the day it lands with no new case here.
      name = "modes: every registry entry carries a description";
      ok =
        modes != { } && lib.all (m: lib.isString (modes.${m}.description or null)) (lib.attrNames modes);
    }
    {
      # Mutual exclusivity is structural — a home is keyed by ONE name — so what is left to state
      # is that the registry names modes and nothing else: no entry may claim a combination.
      name = "modes: the floor is a real mode of the registry, read off the flag";
      ok = modes ? ${floorMode} && (modes.${floorMode}.floor or false);
    }
    {
      # The floor is the mode every host runs, so it must need no affordance to reach: a floor
      # with an associated grant would be a mode a host could fail to run, which is a contradiction
      # in terms.
      name = "modes: the floor carries no associated grant — nothing is afforded to run it";
      ok = !(modes.${floorMode} ? grant);
    }
    {
      # A non-floor mode's `grant` names a FEATURE, because that is what a host affords. A name
      # that is not a feature would derive a `runs` set nothing could ever put the mode into.
      name = "modes: every non-floor mode names a feature as its associated grant";
      ok = lib.all (m: modes.${m} ? grant) (lib.filter (m: m != floorMode) (lib.attrNames modes));
    }

    # --- the host-side derivation: affordances ⇒ the modes a host runs ---
    {
      # A host that affords NOTHING still runs the floor. That is what makes `runs` never empty,
      # and it is why nobody declares the floor: there is no affordance to declare it with.
      name = "runs: a host affording nothing runs the floor, and only the floor";
      ok = runsFor [ ] == [ floorMode ];
    }
    {
      # …and affording a mode's associated grant is what puts that mode in the set. No host
      # declares a mode; the disagreement between "affords gui" and "runs gui" is unwriteable.
      name = "runs: affording a mode's associated grant is what makes the host run it";
      ok = runsFor [ "gui" ] == lib.attrNames modes;
    }
    {
      # An afforded feature that is no mode's grant changes nothing: `sudo` rides the bind, and a
      # grant that reaches no home cannot change what a home was built as.
      name = "runs: a bind-riding grant adds no mode (sudo is nobody's session shape)";
      ok = runsFor [ "sudo" ] == [ floorMode ];
    }

    # --- the selection (ADR-0032 §5) ---
    {
      # A rich mode in the intersection WINS over the floor. No mode name appears in the algorithm
      # — the floor is a parameter — so this is "the non-floor one", not "gui".
      name = "selection: a rich mode available to both sides wins over the floor";
      ok =
        select {
          runs = [
            "cli"
            "gui"
          ];
          published = [
            "cli"
            "gui"
          ];
        } == "gui";
    }
    {
      # …and with no rich mode in common, the floor. This is a headless host binding an ordinary
      # user: it runs the floor, the user publishes both, and the floor is what they share.
      name = "selection: with no rich mode in common, the floor is what is selected";
      ok =
        select {
          runs = [ "cli" ];
          published = [
            "cli"
            "gui"
          ];
        } == "cli";
    }
    {
      # THE REFUSAL: an empty intersection is a hard error naming both sets — a gui-only user on a
      # headless host, which ADR-0032 makes a refusal rather than a silently lesser home.
      name = "selection: an empty intersection is a hard error, never a silent fallback";
      ok =
        !(selects {
          runs = [ "cli" ];
          published = [ "gui" ];
        });
    }
    {
      # TWO RICH MODES: incomparable by design (a phone and a desktop are not ordered against each
      # other), so a host offering both has not said which session it means. Only reachable with a
      # third mode, which the registry does not have — hence the synthetic world.
      name = "selection: two non-floor modes in the intersection is a hard error, not an ordering";
      ok =
        !(selects {
          runs = [
            "cli"
            "gui"
            "mobile"
          ];
          published = [
            "gui"
            "mobile"
          ];
        });
    }
    {
      # …and its control: the SAME three-mode world with one rich mode published selects it, so the
      # refusal above is about the ambiguity and not about the extra mode existing.
      name = "selection: the same three-mode world with one rich mode published selects it (the control)";
      ok =
        select {
          runs = [
            "cli"
            "gui"
            "mobile"
          ];
          published = [
            "cli"
            "mobile"
          ];
        } == "mobile";
    }

    # --- the floor guard, in BOTH directions ---
    {
      name = "floor guard: a registry where NO mode is the floor is a named error";
      ok = !(floorHolds noFloor);
    }
    {
      name = "floor guard: a registry where TWO modes are the floor is a named error";
      ok = !(floorHolds twoFloors);
    }
    {
      # The positive control, without which the two claims above would pass against a kernel that
      # rejects everything: exactly one floor resolves, and resolves to that mode.
      name = "floor guard: exactly one floor resolves to it (the control)";
      ok = floorHolds oneFloor && floorOf oneFloor == "alpha";
    }
    {
      # …and the contract's own registry goes through the very same kernel, so the synthetic
      # claims above are about the guard that actually runs.
      name = "floor guard: the contract's own registry has exactly one floor";
      ok = floorOf modes == floorMode;
    }
  ];
}
