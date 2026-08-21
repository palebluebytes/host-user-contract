# THE contract version — one number, and the only one. It is the repo's release version, owned by
# release-please (docs/adr/0024), and it is also what a manifest declares and what `readManifest`
# refuses a mismatch on. The annotated line below is the bump target: release-please rewrites the
# string there and nothing else, so do not edit it by hand.
#
# It lives in its own plain file rather than in `flake.nix` because `manifest.nix` needs it and a
# flake's outputs are not an importable expression. Threading it through `kit.nix` instead is not
# available: kit takes `{ lib }` and nothing else, and the greeter's runtime evaluators re-import
# `kit.nix` at login with only `lib` in hand (ADR-0020) — a second parameter would break a seat.
#
# There is deliberately no second, narrower "wire format" version. A counter over the manifest's
# field set would gate the wrong thing: the producer↔consumer agreement is also the activation, the
# account plan and the mode groups, none of which such a counter can see. See manifest.nix.
"0.0.0" # x-release-please-version
