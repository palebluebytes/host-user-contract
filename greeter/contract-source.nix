# The CONTRACT'S OWN SOURCE, pinned to the store — the thing the greeter's runtime evaluators
# re-import at login so a rule EXECUTES from its single Nix source instead of being re-spelled in
# jq. Two tools need it (`contract-account-plan` and `contract-select-mode`), so the filter lives
# here rather than twice: a second copy would drift the day a new top-level directory lands, and
# the failure would be a silently fatter login closure.
#
# The filter keeps what `kit.nix` can actually reach (root `*.nix` + `greeter/`) and drops the
# heavy, never-imported trees, so the closure a seat carries is bounded by what the rules need.
# Everything here is contract code over already-authenticated data — no user Nix is in it.
{ pkgs }:
builtins.path {
  path = ./..;
  name = "contract-source";
  filter =
    p: _:
    let
      b = baseNameOf p;
    in
    b != ".git"
    && b != ".direnv"
    && b != ".ruff_cache"
    && b != "conformance"
    && b != "examples"
    && b != "docs"
    && b != ".github"
    && b != ".githooks"
    && !(pkgs.lib.hasPrefix "result" b);
}
