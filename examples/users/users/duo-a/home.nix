# duo-a — the first half of the SHARED-SETUP pair (ADR-0020's "shared code, per-user data"), and
# the members' one worked example of MODE-SPECIFIC HOME CONTENT (issue #55, reshaped by ADR-0032).
#
# duo-a and duo-b exist to prove one thing the other five reference users deliberately do not: that
# an operator CAN enforce a common setup across a set of their own accounts, by importing one shared
# home module and one shared overlay. Since issue #36 that is a permitted bake of the multi-user
# shape rather than an obligation of it — so it gets a live fixture instead of only prose.
#
# What makes duo-a duo-a is its identity.json and its own voice — the desktop it asks for, and the
# content it gates on the mode. The SHARED module it imports is byte-identical to duo-b's, and
# every difference the PAIR is about falls out of `config.identity.username` (see
# `shared/module.nix` and the `shared-code-per-user-data` check); nothing below reaches into it.
#
# duo-a additionally carries the property the whole per-mode home system exists for: its `gui`
# home and its `cli` home differ in REALIZED CONTENT, not merely in a field frozen into the
# manifest. It teaches SUBSTITUTION rather than the same rule spelled twice — graphical content
# beside its terminal counterpart, each present in exactly one mode — which is also what gives
# `custom.home.profiles.cli` its first consumer in this repo. The
# `mode-substitution-is-load-bearing` check fails if the two homes ever converge again.
#
# NOT contract-pure (ADR-0008), by design: the shared module and the leaves below set home-manager
# options, so this home needs home-manager to evaluate — the pair is the members' only
# non-contract-pure member, which is why the gated content lives here rather than being grafted onto
# ada. The conformance tracer borrows ada, never this pair.
{
  config,
  lib,
  ...
}:
let
  inherit (config.custom.home) profiles;
in
{
  # The shared setup, opted into per user — one module, one overlay, both from `../../shared/`.
  imports = [ ../../shared/module.nix ];

  # A home may declare its OWN overlays even though the producer passes `pkgs` explicitly — this
  # list MERGES with the producer's rather than replacing it. Why that holds, and why this overlay
  # needs no `inputs` specialArg, is spelled out once in `shared/overlay.nix`.
  nixpkgs.overlays = [ (import ../../shared/overlay.nix) ];

  # duo-a asks for nothing privileged, so it declares no `contract.wants` (ADR-0028) and its offer
  # is the safe-set default. Its desktop choice differs from duo-b's only to show that sharing a
  # module costs a user none of its own voice.
  contract.requests.gui.desktop = "sway";

  # WHICH SESSIONS THIS HOME CAN RUN IN (ADR-0032) — both, because the substitution below only
  # means anything if the producer builds both and they differ.
  contract.supports.cli = true;
  contract.supports.gui = true;

  # ── UNCONDITIONAL content: works in every mode, so it is written with no gate ────────────────
  # This is the idiom, and the common case: a shell alias file, a git config, an editor rc — none
  # of them care what session they are in, so none of them is gated. `custom.home.profiles.*` is
  # for content that would be WRONG in another mode, not for everything a home ships.
  home.file.".config/duo/common.conf".text = ''
    # duo-a's mode-independent settings — present in the cli home and the gui home alike.
    editor = nvim
  '';

  # ── SUBSTITUTION: the graphical thing, and its terminal counterpart ──────────────────────────
  # `custom.home.profiles.<mode>.enable` is the contract's own switch, DERIVED from `hostFacts.mode`
  # by the home umbrella — exactly one true (ADR-0032 §7). This home writes no wire of its own; it
  # only gates on the vocabulary, which is what the vocabulary is for.
  #
  # The two leaves are counterparts, not an addition and its absence: the same concern (how this
  # user drives windows) answered the way each session can answer it. That is the difference the
  # per-mode build exists to carry — no bind-time grant could put a sway config into a home built
  # for a terminal, which is precisely what makes a MODE a mode and not a grant.
  home.file.".config/sway/config" = lib.mkIf profiles.gui.enable {
    text = ''
      # duo-a's sway config — the GUI leaf, present only in the home built for the gui mode.
      set $mod Mod4
      bindsym $mod+Shift+q kill
    '';
  };
  home.file.".config/tmux/tmux.conf" = lib.mkIf profiles.cli.enable {
    text = ''
      # duo-a's tmux config — the CLI counterpart of the sway config above: the same concern
      # (window management) as a terminal session can answer it. This is `custom.home.profiles.cli`'s
      # first consumer in this repo; commit 267a545 had stripped the write precisely because
      # nothing read it.
      set -g prefix C-a
      bind | split-window -h
    '';
  };
}
