# THE contract version — one number, and the only one. Release-please owns this file and rewrites
# the string on the annotated line; do not edit it by hand (docs/adr/0024).
#
# `manifest.nix` imports it and gates on it: a manifest is accepted when its version shares this
# one's compatibility line, so a published package binds until a MAJOR release.
"0.1.0" # x-release-please-version
