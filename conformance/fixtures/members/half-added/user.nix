# A half-added user: the user.nix landed, the identity.json has not. The member set must skip this
# directory rather than derive a member whose identity read throws.
{
  contract.cli.enable = true;
}
