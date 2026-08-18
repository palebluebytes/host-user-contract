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
lib.mapAttrs (_: m: { enable = lib.mkEnableOption m.description; }) modeRegistry
