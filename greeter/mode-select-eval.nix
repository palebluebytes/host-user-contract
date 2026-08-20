# contract-select-mode: the runtime evaluator that makes `selectModeOver` the ONE owner of mode
# selection, on both paths.
#
# A declarative bind selects in Nix; a greeter selects at a login prompt, in a shell. The obvious
# thing — reimplement the rule in jq — is what this file exists to avoid, and the reason is not
# tidiness: the two spellings had already diverged. The Nix kernel REFUSES two non-floor modes by
# name (a phone and a desktop are incomparable, so a host offering both has not said which session
# it means); a jq transcription of it silently took the first. Unreachable while the registry has
# one non-floor mode, and wrong the day it gains a second — which is precisely the case the floor
# FLAG, rather than a total rank, exists for.
#
# So the rule EXECUTES from its single Nix source at login, exactly as `contract-account-plan` does
# for the account-combining fold, and for the same reason. It is CONTRACT-OWNED code over
# ALREADY-AUTHENTICATED data, run AFTER the eval-free auth gate — it evaluates no USER Nix at all.
# The user's flake IS evaluated at this step, but by the bind orchestrator, one call earlier and
# under the Tier-1 restricted-eval posture; what reaches this tool is a JSON list of mode names.
#
# It runs UNRESTRICTED for the same reason `contract-account-plan` does: the restricted posture is
# scoped to the home BUILD, and this is a one-shot login computation over the contract's own
# source, not a reproducible build.
#
# THE SHELL THAT CALLS THIS KNOWS NO MODE NAME. The fallback is `kit.floorMode`, read from the
# contract source; the seat's RUN SET is a fact about this machine (`contract.modes`), so it is
# frozen to a store file at build time and read from there — the same way `provision` reads the
# grant and the seat groups. It cannot come from the contract source, because the contract does not
# know whether this box has a display; that was the bug this whole split exists to fix.
{
  pkgs,
  # The seat's run set, frozen to store JSON by greeter.nix. A build-time fact, in the seat's own
  # closure — `cat` it and you know what this machine will offer a stranger.
  runsFile,
  # The contract source, pinned to the store; the filter lives in ./contract-source.nix.
  src ? import ./contract-source.nix { inherit pkgs; },
  # A nixpkgs `lib` source for the runtime eval — the nixpkgs the seat already builds with.
  nixpkgsPath ? pkgs.path,
}:
let
  # The evaluation, frozen to a store file. Only `kit.internal.selectModeOver` and `kit.floorMode`
  # are forced, so the rest of the kit stays a lazy thunk at login.
  #
  # AN ABSENT PUBLISHED SET IS THE FLOOR, and that answer is given HERE rather than by the caller:
  # every host runs the floor by construction, so it is the one mode that is always a truthful
  # answer, and putting the fallback beside the selection keeps the shell free of mode names.
  exprFile = pkgs.writeText "contract-select-mode.nix" ''
    let
      lib = import ${nixpkgsPath}/lib;
      kit = import ${src}/kit.nix { inherit lib; };
      publishedFile = builtins.getEnv "CONTRACT_PUBLISHED";
    in
    if publishedFile == "" then
      kit.floorMode
    else
      kit.internal.selectModeOver {
        who = "greeter";
        subject = builtins.getEnv "CONTRACT_SUBJECT";
        floor = kit.floorMode;
        runs = builtins.fromJSON (builtins.readFile ${runsFile});
        published = builtins.fromJSON (builtins.readFile publishedFile);
      }
  '';
in
pkgs.writeShellApplication {
  name = "contract-select-mode";
  runtimeInputs = [ pkgs.nix ];
  text = ''
    subject=''${1:-}
    published=''${2:-}
    [ -n "$subject" ] || {
      echo "usage: contract-select-mode <username> [published-modes.json]" >&2
      exit 1
    }
    if [ -n "$published" ] && [ ! -r "$published" ]; then
      echo "contract-select-mode: cannot read published modes '$published'" >&2
      exit 1
    fi

    # Evaluate the contract's own selection kernel and print the chosen mode. A refusal (no mode in
    # common, or two incomparable rich modes) throws the contract's own named diagnostic and exits
    # non-zero — the same message a declarative bind would print, because it is the same throw.
    export CONTRACT_SUBJECT="$subject"
    export CONTRACT_PUBLISHED="$published"
    exec nix eval --impure --raw --extra-experimental-features nix-command -f ${exprFile}
  '';
}
