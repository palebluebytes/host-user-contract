# accountPlan (issue #30, deepening candidate 02) — the single, pure description of how an
# identity and its grants become a system account. It is the SHARED plan the build-time and
# runtime adapters both render: `realization.nix` maps it into `users.users` (build time, here),
# and the greeter's runtime provisioning will render the same record to data (issue #31).
#
# It is deliberately a NEUTRAL account record — the four semantic account fields as flat data, not
# the NixOS `users.users` module SHAPE (no `isNormalUser` framing, no `openssh.authorizedKeys.keys`
# nesting; `authorizedKeys` is a plain list) — so the runtime side can serialize it (GECOS, password,
# authorized_keys lines, the clamped+granted groups) directly. Field NAMES overlap `users.users`, but
# the shape does not. Each adapter owns its own shape mapping; this owns the identity→account
# field DERIVATION:
#   - description / GECOS ..... the identity's display name;
#   - hashedPassword .......... the login credential (a one-way hash), carried verbatim;
#   - authorizedKeys .......... the login keys — the primary `sshKey` (dropped when empty) then
#                               the `trustedKeys`, in that order;
#   - extraGroups ............. the clamped self-declared groups ∪ the groups the grant confers.
#
# The clamp and the grant→groups fold both come from the injected grantLib (issue #28) — the
# single owner of the security-critical privileged-group clamp — so this plan cannot drift from
# the greeter's runtime `provision`, which reproduces the same rule shell-side. `grants` is a
# grant attrset (`{ <feature> = bool; }`, i.e. `custom.users.<u>.granted`); `identity` is
# the resolved identity record. Pure: no `config`, no module args, no packages (ADR-0004).
{
  lib,
  grantLib,
}:
{
  accountPlan =
    {
      identity,
      grants,
    }:
    {
      description = identity.name;
      inherit (identity) hashedPassword;
      # The primary key is optional (a real user may ship `sshKey = ""`); trustedKeys follow it.
      authorizedKeys = lib.optional (identity.sshKey != "") identity.sshKey ++ identity.trustedKeys;
      # Self-declared groups with privileged ones clamped out (untrusted input) ∪ the privileged +
      # input groups the granted features confer. Privilege can only enter via a grant.
      extraGroups = lib.unique (
        grantLib.safeDeclared identity.extraGroups ++ grantLib.grantedGroups grants
      );
    };
}
