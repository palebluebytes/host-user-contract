# agent — an EXPOSED, headless host (`contract.exposed = true`).
#
# `exposed` is a plain host fact an operator records; the contract enforces nothing on it.
#
# It declares NO modes, so it runs the floor alone — and affords nothing to either user it binds.
# Both dimensions at their most restrictive, and note that they are restrictive for different
# reasons: no display is an INCAPACITY of the box, while no sudo is a DECISION about a person.
#   - ada: the SAME ada who logs into a desktop on `desk`. This machine runs only `cli`, so
#     selection binds her CLI home — no display surface, no input groups. One identity, one source,
#     the opposite session, because the hardware differs.
#   - svc: an account that runs in a terminal and nowhere else, by its own declaration — so even a
#     seat WITH a display would have no gui home of svc's to select.
{ contract, users, ... }:
{
  contract.exposed = true;

  imports = [
    (contract.lib.bindContractUsers {
      source = users;
      users = {
        ada = { };
        svc = { };
      };
    })
  ];

  networking.hostName = "agent";
}
