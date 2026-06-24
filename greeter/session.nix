# (8) the session launcher: the greeter SELECTS the desktop, the HOST binds the backend.
# Usage: contract-greeter-session <username> <home-dir>
# ADR-0029: the contract resolves the user's chosen DESKTOP (surfaced from the bound home as
# ~/.contract-desktop, else the seat default) against the desktops the SEAT offers, and execs that
# desktop's command AS the user in greetd's seat session. The contract ships no desktop (ADR-0020).
{
  pkgs,
  lib,
  desktops,
  defaultDesktop,
}:
let
  # The desktops this seat offers, baked into a shell `case` the launcher resolves the user's
  # requested desktop against (ADR-0029). Each arm sets the session type + the launch command.
  desktopArms = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: d:
      "        ${lib.escapeShellArg name}) dtype=${lib.escapeShellArg d.type}; dcmd=${lib.escapeShellArg d.command} ;;"
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
          defaultDesktop=${lib.escapeShellArg defaultDesktop}

          # Resolve a desktop NAME to its session type + launch command (the seat's offered desktops).
          resolve() {
            case "$1" in
    ${desktopArms}
              *) return 1 ;;
            esac
          }

          # The user's chosen desktop is surfaced from their home (~/.contract-desktop, materialised from
          # contract.requests.gui.desktop); absent ⇒ the seat default.
          if [ -f "$home/.contract-desktop" ]; then
            want=$(cat "$home/.contract-desktop")
          else
            want=$defaultDesktop
          fi

          # An un-offered/unknown desktop degrades to the seat default — never breaks the login (ADR-0029).
          dtype=""; dcmd=""
          if ! resolve "$want"; then
            echo "session: desktop '$want' not offered by this seat; using default '$defaultDesktop'" >&2
            resolve "$defaultDesktop" || { echo "session: no default desktop offered (custom.greeter.desktops/defaultDesktop)" >&2; exit 1; }
          fi
          [ -n "$dcmd" ] || { echo "session: resolved desktop has no command" >&2; exit 1; }

          # The session must run AS the user, in a SEAT session, for the compositor/DE/Xorg to get DRM
          # and a systemd-user instance — which is greetd's job (it creates the logind seat session and
          # runs this command as the user). So when already the user (greetd's model) exec in place; only
          # drop privs with runuser when invoked by the root orchestrator (which is NOT a seat session —
          # that path suits headless/marker backends, not a real GPU session). ADR-0026/0029 step 8.
          if [ "$(id -un)" = "$username" ]; then
            exec env HOME="$home" XDG_SESSION_TYPE="$dtype" bash -c "$dcmd"
          else
            exec runuser -u "$username" -- env HOME="$home" XDG_SESSION_TYPE="$dtype" bash -c "$dcmd"
          fi
  '';
}
