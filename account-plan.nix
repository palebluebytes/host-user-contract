# accountPlan — the single, pure description of how an identity, its grants and its session shape
# become a system account. It is the SHARED plan both adapters render: `realization.nix` maps it
# into `users.users` at build time, and the greeter's `provision` renders the same record to data
# at login, so the security-critical rule below cannot drift between them.
#
# It is deliberately a NEUTRAL account record — the four semantic account fields as flat data, not
# the NixOS `users.users` module SHAPE (no `isNormalUser` framing, no `openssh.authorizedKeys.keys`
# nesting; `authorizedKeys` is a plain list) — so the runtime side can serialize it directly. Field
# NAMES overlap `users.users`, but the shape does not. Each adapter owns its own shape mapping;
# this owns the identity→account field DERIVATION:
#   - description / GECOS ..... the identity's display name;
#   - hashedPassword .......... the login credential (a one-way hash), carried verbatim;
#   - authorizedKeys .......... the login keys — the primary `sshKey` (dropped when empty) then
#                               the `trustedKeys`, in that order;
#   - extraGroups ............. what the MODE needs ∪ what the GRANT confers.
#
# TWO GROUP SOURCES, AND NOTHING SELF-DECLARED. An account's groups are decisions somebody else
# made: what the session shape needs in order to run at all (a graphical session's input devices,
# which ride the MODE because needing them is a property of running that session), and what the
# host afforded this person (which rides the GRANT because it is a judgement about them).
#
# There is no third source. An identity used to carry `extraGroups` — group names a user wrote into
# their own public record — filtered by a deny-list of privileged names, so anything outside that
# list reached the account unconditionally. That is gone: a user cannot put themselves in a group,
# so there is no untrusted group input left to filter.
#
# The mode's own groups still run through the privileged filter, and that is not vestigial — it is
# the one line stopping a privileged name added to `modes.nix` from reaching every account in that
# mode with no grant. The registry is contract-owned, so the conformance suite catches it loudly
# too; this makes the failure SAFE as well as loud.
#
# `grants` is `{ <feature> = bool; }` (i.e. `contract.users.<u>.granted`); `mode` is the session
# shape this account was bound in; `identity` is the resolved identity record. Pure: no `config`,
# no module args, no packages.
{
  lib,
  grantLib,
  modeRegistry,
}:
{
  accountPlan =
    {
      identity,
      grants,
      # The session shape this account runs in. A mode the registry does not name contributes no
      # groups rather than throwing: this is a pure fold rendered at login as well as at build
      # time, and the place a bad mode name is caught is the registry-typed surface it came from.
      mode,
    }:
    {
      description = identity.name;
      inherit (identity) hashedPassword;
      # The primary key is optional (a real user may ship `sshKey = ""`); trustedKeys follow it.
      authorizedKeys = lib.optional (identity.sshKey != "") identity.sshKey ++ identity.trustedKeys;
      # What this session shape needs, plus what the granted features confer. Privilege can only
      # enter through a GRANT — mode groups are non-privileged by construction, and one that was
      # not would be dropped here rather than conferred.
      extraGroups = lib.unique (
        grantLib.withoutPrivileged (modeRegistry.${mode}.groups or [ ]) ++ grantLib.grantedGroups grants
      );
    };
}
