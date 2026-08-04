# ben — the secret-bearing reference user.
#
# ben OFFERS a commit-signing key (the `signing` feature — secret-bearing, ADR-0001 threat model).
# A host GRANTS it only where it is safe to: on a non-exposed host the grant lands; an EXPOSED host
# may never be granted a secret-bearing feature (the exposed-host ban), so the fleet simply does not
# run ben there. The signing secret rides ben's OWN home sops, decrypted by ben's own key — no host
# re-key, no host recipients (features.signing has no secretFiles) — so ben's `secrets/` is
# encrypted to ben alone (ADR-0020 per-user isolation), and the home module owns its provisioning.
#
# Contract-pure (ADR-0008): only contract/home-profile options, no home-manager options, so it
# harvests headlessly in the conformance tracer.
{ ... }:
{
  # The home meta-profiles ben's home offers. `signing.enable` is the home-side signal that this
  # user carries a commit-signing key; the matching home config (the git backend) is supplied by
  # ben's own home module in a real build — the contract ships only the vocabulary (ADR-0008).
  custom.home.profiles = {
    cli.enable = true;
    signing.enable = true;
  };
}
