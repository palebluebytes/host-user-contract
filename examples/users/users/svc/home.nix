# svc — the user-side veto.
#
# Every other reference user demonstrates the HOST half of `grant = affordances ∩ offer`: ada is gui
# on a seat that affords gui and cli-only on a headless box, so the HOST varies the outcome. svc is
# the only one demonstrating the USER half — it refuses gui, so NO host can grant it a display
# surface however much it affords one. The veto is symmetric: either party can independently say no,
# and neither can override the other's refusal.
#
# It signs in like any other user (it carries a login credential — ADR-0019, cleartext
# "correct-horse-battery-staple", the members' shared reference password). That is deliberate: this
# contract delivers "login, dotfiles, the features they need" (ADR-0001), so a reference user is one
# that logs in. What makes svc distinct is not that it never takes a seat — it is that it never
# takes a DESKTOP, on any host, by its own choice.
#
# Contract-pure (ADR-0008), and down to a single line of voice: the veto itself. Like every
# contract-pure home it declares no `custom.home.profiles.*`, having no content to gate (see the
# contract's `home-profiles.nix`).
{ ... }:
{
  # What svc asks a host for (ADR-0028): everything non-privileged EXCEPT gui — the explicit
  # OPT-OUT. Every safe-set feature is wanted by default, so an account that must never get a
  # desktop has to say so; this is the one line that keeps "never gui" true even on a seat that
  # affords it, and the only worked example of that escape hatch in the repo.
  #
  # It is also why this home carries NO `contract.requests.gui.*`: gui parameters beside a gui veto
  # could never bridge on any host, so they are dead data and the bake rejects them (issue #59). The
  # ADR-0002 case is the other one — a request the HOST does not grant stays silently inert.
  contract.wants.gui = false;

  # …and the mode goes with the want (ADR-0032): a home that vetoes the gui GRANT and still claimed
  # the gui MODE is a contradiction no host can rescue, and the bake refuses it by name. svc runs
  # in a terminal, and says only that.
  contract.supports.cli = true;
}
