# contract-select-mode (ADR-0020): the runtime evaluator that makes `selectModeOver` the ONE owner
# of mode selection, on both paths — the greeter EXECUTES the kernel rather than re-spelling it in
# jq, which is the duplication that had already drifted.
#
# CONTRACT-OWNED code over ALREADY-AUTHENTICATED data, run AFTER the eval-free auth gate, so it
# evaluates no USER Nix. The user's flake IS evaluated at this step, but by the bind orchestrator,
# one call earlier and under the Tier-1 restricted-eval posture (ADR-0019); what reaches this tool
# is a JSON list of mode names.
#
# THE SHELL THAT CALLS THIS KNOWS NO MODE NAME. The fallback is `kit.floorMode`, read from the
# contract source. The seat's RUN SET cannot come from there — the contract does not know whether
# this box has a display — so it is a fact about this machine (`contract.modes`), frozen to a store
# file at build time and read from there, the same way `provision` reads the grant and the seat
# groups.
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
