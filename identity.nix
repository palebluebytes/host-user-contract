# Shared declaration of the per-user identity option set. Used by BOTH umbrella modules so the
# system-level `contract.users.<user>.identity` submodule and the home-level `identity` options
# describe the same data and can't drift; the host bridges the two when it binds a user.
#
# AN IDENTITY DESCRIBES A PERSON, NEVER THEIR POWERS. Every field here is either descriptive (name,
# email, gmail) or a login credential (hashedPassword, sshKey, trustedKeys) — nothing in it decides
# what an account may DO, and nothing in it reaches host state on its own.
#
# It used to carry `extraGroups`, and that was the exception: a user wrote group names into their
# own public record and a host materialized them, filtered by a deny-list of privileged names.
# Anything outside that list — `networkmanager`, say — passed through unconditionally, which on the
# greeter path meant a stranger could put themselves in it by editing their own file. It is gone.
# An account's groups now come from exactly two places, and both are decisions somebody else made:
# the SESSION it was bound in (`modes.<m>.groups`) and what the HOST afforded (`affordances`).
{ lib }:
{
  name = lib.mkOption {
    type = lib.types.str;
    description = "User's full name";
  };
  email = lib.mkOption {
    type = lib.types.str;
    description = "User's email address";
  };
  gmail = lib.mkOption {
    type = lib.types.str;
    description = "User's gmail address";
    default = "";
  };
  sshKey = lib.mkOption {
    type = lib.types.str;
    description = "User's public SSH key";
    default = "";
  };
  username = lib.mkOption {
    type = lib.types.str;
    description = "System username";
  };
  hashedPassword = lib.mkOption {
    type = lib.types.str;
    description = "User's hashed password";
    default = "";
  };
  trustedKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    description = "List of trusted public SSH keys for this user";
    default = [ ];
  };
}
