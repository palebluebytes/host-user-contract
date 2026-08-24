# (8) the session launcher: the greeter SELECTS the desktop, the HOST binds the backend.
# Usage: contract-greeter-session <username> <home-dir> [desktop]
# ADR-0021: the contract resolves the user's chosen DESKTOP against the desktops the SEAT offers and
# execs that desktop's command AS the user in greetd's seat session. The contract ships no desktop
# (ADR-0002).
#
# THE DESKTOP ARRIVES AS AN ARGUMENT, from whoever selected the mode it is a parameter of — the
# orchestrator reads it off the user's published binding index in the same eval that reads their
# modes (./bind.nix). It is not read out of the home: a mode parameter is a fact about the USER, and
# the index is where a reader already looks for those without opening a built home (ADR-0021). An
# empty or omitted argument is the ordinary case — the seat's default is used — so a caller that has
# no value to pass simply does not pass one.
{
  pkgs,
  lib,
  desktops,
  defaultDesktop,
}:
let
  # The desktops this seat offers, baked into a shell `case` the launcher resolves the user's
  # requested desktop against (ADR-0021). Each arm sets the launch command; the command is
  # self-contained — the seat owns the session type, not the contract (ADR-0021).
  desktopArms = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: d: "        ${lib.escapeShellArg name}) dcmd=${lib.escapeShellArg d.command} ;;"
    ) desktops
  );
in
pkgs.writeShellApplication {
  name = "contract-greeter-session";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.util-linux
    pkgs.bash
  ];
  text = ''
          username=$1
          home=$2
          # The user's chosen desktop, selected by the caller. Absent/empty ⇒ the seat default.
          want=''${3:-}
          defaultDesktop=${lib.escapeShellArg defaultDesktop}
          [ -n "$want" ] || want=$defaultDesktop

          # Resolve a desktop NAME to its launch command (the seat's offered desktops).
          resolve() {
            case "$1" in
    ${desktopArms}
              *) return 1 ;;
            esac
          }

          # An un-offered/unknown desktop degrades to the seat default — never breaks the login (ADR-0021).
          dcmd=""
          if ! resolve "$want"; then
            echo "session: desktop '$want' not offered by this seat; using default '$defaultDesktop'" >&2
            resolve "$defaultDesktop" || { echo "session: no default desktop offered (contract.greeter.desktops/defaultDesktop)" >&2; exit 1; }
          fi
          [ -n "$dcmd" ] || { echo "session: resolved desktop has no command" >&2; exit 1; }

          # The session must run AS the user, in a SEAT session, for the compositor/DE/Xorg to get DRM
          # and a systemd-user instance — which is greetd's job (it creates the logind seat session and
          # runs this command as the user). So when already the user (greetd's model) exec in place; only
          # drop privs with runuser when invoked by the root orchestrator (which is NOT a seat session —
          # that path suits headless/marker backends, not a real GPU session). ADR-0021.
          if [ "$(id -un)" = "$username" ]; then
            exec env HOME="$home" bash -c "$dcmd"
          else
            exec runuser -u "$username" -- env HOME="$home" bash -c "$dcmd"
          fi
  '';
}
