# admin — a break-glass administrative reference user (ADR-0020's "break-glass admin").
#
# Its distinction is the GRANT a host gives it, not its home: bound with the `sudo` feature, it
# receives `wheel` — administrative access and NOTHING more, the MINIMAL privileged grant (contrast
# cleo, whose atomic `containers` grant confers docker/podman and no wheel — ADR-0024). Its login password is the well-known
# cleartext "password" (identity.json's hashedPassword) — a deliberately trivial break-glass
# credential for a reference account, and a demonstration that the login credential travels with the
# user as public data (ADR-0019).
#
# Contract-pure (ADR-0008): cli-only, no home-manager options — and so no `custom.home.profiles.*`,
# which is a switch a home gates its own content on (see the contract's `home-profiles.nix`).
{ ... }:
{
  # What admin ASKS a host for (ADR-0028): `sudo` is privileged, so it must be asked for
  # explicitly. It stays an ask — wheel arrives solely where a host also affords sudo
  # (grant = affordances ∩ offer), and the producer harvests this as admin's published offer.
  contract.wants.sudo = true;

  # WHICH SESSIONS THIS HOME CAN RUN IN (ADR-0032). A break-glass account has to be reachable from
  # a terminal above all, and it takes a desktop where one is offered.
  contract.supports.cli = true;
  contract.supports.gui = true;
}
