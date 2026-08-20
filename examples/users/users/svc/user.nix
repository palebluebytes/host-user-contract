# svc — the account that is never graphical, anywhere.
#
# It is the whole of the user-side veto, and it needs no veto mechanism to say it: svc runs in a
# terminal and declares nothing else, so there is no gui home for any host to select. A seat that
# runs the gui mode for everybody still binds svc to a terminal session, because selection can only
# choose among the modes a user actually runs in.
#
# That is why this contract has no `wants`. The refusal a user genuinely needs is "never give me a
# desktop", and it is already expressible by not enabling the mode. The refusal a user does NOT get
# is "never give me sudo", because a host that afforded sudo has decided that, and a second
# authority over the same value with nothing forcing the two to agree is a defect rather than a
# safeguard.
#
# It signs in like any other user (it carries a login credential — cleartext
# "correct-horse-battery-staple", the members' shared reference password). That is deliberate: this
# contract delivers login, dotfiles and the features a host confers, so a reference user is one
# that logs in.
{
  contract.cli.enable = true;
}
