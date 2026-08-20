# admin — a break-glass administrative reference user.
#
# Its distinction is entirely the HOST's: bound with `affordances.sudo = true`, it receives `wheel`
# — administrative access and nothing more, the minimal privileged grant (contrast cleo, whose
# atomic `containers` affordance confers docker/podman and no wheel). Nothing in this file asks for
# that, because a user does not ask for powers: which groups an account lands in is the host's
# decision, stated where the host binds it.
#
# Its login password is the well-known cleartext "password" (identity.json's hashedPassword) — a
# deliberately trivial break-glass credential for a reference account, and a demonstration that the
# login credential travels with the user as public data.
{
  # A break-glass account has to be reachable from a terminal above all, and it takes a desktop
  # where one is offered.
  contract.cli.enable = true;
  contract.gui.enable = true;
}
