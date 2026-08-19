# Home meta-profile options — part of the host↔user contract (ADR-0001).
# Declared by the home umbrella module as `custom.home.profiles.*`.
#
# ONE OPTION PER MODE, derived from the mode registry (`modes.nix`) so the switch vocabulary and
# the session-shape vocabulary cannot drift: a contract that gains a mode gains its profile with
# no edit here, and a home gating on a mode the contract does not name is an eval error.
#
# THE CONTRACT WRITES THESE (ADR-0032 §7), reversing this file's earlier rule that it declared them
# and never wrote them. `hostFacts.mode` is the single source, and the home umbrella derives
# exactly one `true` from it — the mode is a fact handed TO the home, not a choice the home makes,
# which is why a home writing one is a conflicting definition rather than an override. What a home
# does with it is unchanged: leaf modules gate on the familiar `lib.mkIf profiles.gui.enable`.
#
# It is distinct from the user's `contract.supports`, which is what this home CAN run in — the user
# speaking outward, and what the producer publishes against. One is a claim; this is the answer.
#
# THE CONTENT IDIOM follows from exactly-one-true: content that works in EVERY mode is written
# unconditionally (a `git.nix` belongs in the gui home and the cli home alike, with no gate), and
# only mode-specific content is gated. A user supporting one mode gates nothing at all; the
# deliberate work a cli-aware author does is declaring `contract.supports.cli = true` and then
# gating the gui-only parts. The worked example is `examples/users/users/duo-a`, which substitutes
# a graphical config for its terminal counterpart.
{ lib, modeRegistry }:
lib.mapAttrs (_: m: {
  # Written out rather than `mkEnableOption`, whose "Whether to enable …" is the wrong sentence
  # for an option a home may not enable. This description is what a home's author is shown the
  # moment they get it wrong — a home that writes one gets a CONFLICTING DEFINITION from the
  # module system, and that report names the option and nothing else — so it is the only place
  # the rule can be stated where the error will find it.
  enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether the home is running in ${m.description}.

      READ-ONLY to a home. The contract writes every one of these from `hostFacts.mode` — the
      single mode this home was BUILT for — so exactly one is true and a home only ever gates on
      it (`lib.mkIf config.custom.home.profiles.<mode>.enable`). Setting one from a home is a
      conflicting definition rather than an override: the mode is a fact handed TO the home, and
      a home cannot choose what it was built as. To change it, build the home for a different
      mode (`mkContractHome { mode = …; }`), and declare the modes the user can run in with
      `contract.supports`.
    '';
  };
}) modeRegistry
