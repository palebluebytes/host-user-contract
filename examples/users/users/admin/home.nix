# admin — a break-glass administrative reference user (ADR-0020's "break-glass admin").
#
# Its distinction is the GRANT a host gives it, not its home: bound with the `sudo` feature, it
# receives `wheel` — administrative access and NOTHING more, the MINIMAL privileged grant (contrast
# cleo, whose atomic `containers` grant confers docker/podman and no wheel — ADR-0024). Its login password is the well-known
# cleartext "password" (identity.json's hashedPassword) — a deliberately trivial break-glass
# credential for a reference account, and a demonstration that the login credential travels with the
# user as public data (ADR-0019).
#
# Contract-pure (ADR-0008): cli-only, no home-manager options.
{ ... }:
{
  # admin's OFFER (ADR-0028): `sudo` is privileged, so it must be asked for explicitly. It is
  # still only an ASK — wheel arrives solely where a host also affords sudo (affordances ∩ offer).
  contract.wants.sudo.enable = true;
  custom.home.profiles.cli.enable = true;
}
