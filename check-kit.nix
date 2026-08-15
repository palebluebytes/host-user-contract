# The contract's CHECK KIT (issue #35) — proofs a CONSUMER runs over its OWN repo, shipped so
# every user/host repo calls one function instead of re-deriving a technique it can get subtly
# wrong. Distinct from `conformance/`, which proves the contract's own promises in isolation:
# these two checks can only be run where the consumer's real material lives (its actual module
# imports, its actual roster of identities), which is exactly why the contract cannot make them
# for anyone and must hand them over as functions.
#
# Lib-only and package-free (ADR-0004): this file is a pure function of `lib`. Each check takes
# the caller's `pkgs` (for the trivial `runCommand` witness) and — crucially for the confinement
# check — the caller's OWN home builder, so the contract never needs home-manager to prove a
# home-manager module set. Both fail LOUDLY at eval with a named message, the same posture as
# every other contract guard (`assert lib.assertMsg …`), so a failing check reports WHICH claim
# broke rather than a build log to read.
{ lib }:
let
  # The negative space itself (ADR-0002): system options a confined user home must be unable to
  # NAME. Each is a real NixOS/sops option a user might reach for to escalate; the home umbrella
  # declares none of them, so each throws "option does not exist" at eval. Single-sourced here and
  # read BOTH by `mkConfinementCheck` below and by the contract's own umbrella proof
  # (`conformance/confinement.nix`, via kit.internal) — one list of "what a user must not be able
  # to say", so a newly recognised escalation path cannot land in one copy and not the other.
  outOfUniverseProbes = {
    "users.users" = {
      users.users.root.hashedPassword = "!escalate";
    };
    "security.sudo" = {
      security.sudo.wheelNeedsPassword = false;
    };
    "boot.loader" = {
      boot.loader.grub.enable = true;
    };
    "sops.secrets" = {
      sops.secrets."steal".sopsFile = "/dev/null";
    };
    # A privileged group grab via the system account option (grants flow the other way — the host
    # adds groups `mkIf granted`, ADR-0003).
    "users.users.extraGroups" = {
      users.users.example.extraGroups = [ "wheel" ];
    };
  };

  # The credential postures — exactly the TWO ADR-0019 names, as prefix rules over
  # `identity.json`'s `hashedPassword` (a crypt hash's `$id$` prefix IS its algorithm label):
  # "**Private repo** — any libc-`crypt` hash (`$6$` sha512crypt is fine) … **Public / shared
  # repo** — **yescrypt** (`$y$`)". No third posture is invented here: a posture a repo can ask
  # for is a decision ADR-0019 made, and this table only spells each one once so no repo
  # hand-writes a `$y$` comparison. Each carries its remedy, so a failure says how to fix itself.
  credentialPostures = {
    # Public / shared repo: the hash is world-readable, so it must be memory-hard.
    yescrypt = {
      prefixes = [ "$y$" ];
      description = "yescrypt (`$y$`) — the public/shared-repo posture";
      remedy = "mkpasswd -m yescrypt";
    };
    # Private repo: any libc-crypt hash. Still rejects an EMPTY or non-crypt field — "some hash"
    # is a posture, "no credential at all" is not.
    libc = {
      prefixes = [
        "$y$"
        "$gy$"
        "$7$"
        "$6$"
        "$5$"
        "$2b$"
        "$2y$"
        "$2a$"
        "$1$"
      ];
      description = "any libc-crypt hash — the private-repo posture";
      remedy = "mkpasswd -m yescrypt (any libc method qualifies)";
    };
  };

  # What a passing check looks like: an empty witness derivation. Both checks fail at EVAL (a
  # named `assert`), so the derivation exists only to be something `checks.<system>.<name>` can
  # point at — single-sourced so the two cannot drift into different shapes.
  okWitness = pkgs: name: pkgs.runCommand "${name}-ok" { } "touch $out";
in
{
  inherit outOfUniverseProbes;

  # mkConfinementCheck (issue #35): prove a consumer's REAL module set has no system channel.
  #
  # `conformance/confinement.nix` proves the contract UMBRELLA is confined — the right proof for
  # the contract's own suite, and only half the promise. A consumer needs the other half: that its
  # own imports (a shared home module, a sops-nix backend, an overlay's module) did not smuggle a
  # system channel back in. That proof can only run where those imports are, so the contract ships
  # the technique instead of the verdict.
  #
  # SIGNATURE — the caller passes its own home BUILDER, which is what keeps this package-free and
  # home-manager-free (ADR-0004): the contract never imports home-manager, it only applies a
  # function the consumer supplies. A typical user repo already has one:
  #
  #     contract.lib.mkConfinementCheck {
  #       inherit pkgs;
  #       buildHome = extraModules: mkHome { userDir = ./users/ada; identity = adaId; extra = extraModules; };
  #     }
  #
  # `buildHome` takes a LIST of extra modules (the check appends exactly one probe at a time) and
  # returns the consumer's evaluated home. `force` then forces that home hard enough to run the
  # module system's unmatched-definition check — by default `activationPackage.drvPath`, the
  # home-manager shape ~every consumer has; a hand-rolled `evalModules` home overrides it (e.g.
  # `force = c: c.some.declared.option`). It is a hook rather than an assumption because the
  # contract cannot know the consumer's home shape, and a home that is never forced would make the
  # whole check vacuous.
  #
  # It CANNOT pass vacuously, in either direction — the two ways this check is got wrong by hand:
  #   - reject-everything (a broken builder, a typo'd path): every out-of-universe probe "fails to
  #     evaluate" and the check looks green. The POSITIVE CONTROL closes this — a legitimate home
  #     option must still evaluate. This is the part people forget, so it is not optional here.
  #   - force-nothing (a lazily-returned home): every probe "evaluates" and the negative claims
  #     fail loudly. So an under-forcing `force` breaks the check LOUDLY rather than silently.
  #
  # An eval failure `tryEval` cannot catch (an infinite recursion from a module set that is BROKEN
  # rather than merely permissive) propagates raw: still a failing check, but reported as the
  # underlying error instead of the messages below.
  #
  # COVERAGE NOTE — `conformance/confinement.nix` drives this function's logic through a synthetic
  # home-manager-free builder (it has to: ADR-0004). The two DEFAULTS a real consumer relies on —
  # `force = home.activationPackage.drvPath` and the `home.sessionVariables` positive control —
  # are therefore only exercised where home-manager actually exists, i.e. in a consumer repo's own
  # `checks`. Keep them in step with home-manager's option names.
  mkConfinementCheck =
    {
      buildHome,
      pkgs,
      name ? "home-confinement",
      force ? (home: home.activationPackage.drvPath),
      # A legitimate home option — the control that proves the builder still says yes to something.
      # Defaults to a home-manager option (a session variable: no packages, no closure), since the
      # builder is a home-manager one by default.
      positiveControl ? {
        home.sessionVariables.CONTRACT_CONFINEMENT_CONTROL = "ok";
      },
    }:
    let
      # Does the home still evaluate with this one extra module merged in? An UNDECLARED option
      # throws inside the module system, caught here as `success = false`.
      evaluates = mod: (builtins.tryEval (force (buildHome [ mod ]))).success;
      expressible = lib.filter (path: evaluates outOfUniverseProbes.${path}) (
        lib.attrNames outOfUniverseProbes
      );
      controlOk = evaluates positiveControl;
    in
    # Ordered deliberately: report a broken harness BEFORE reporting confinement, or a builder
    # that rejects everything would be read as a passing check with a strange name.
    assert lib.assertMsg controlOk (
      "${name}: the POSITIVE CONTROL did not evaluate — this module set rejects even a legitimate "
      + "home option, so its rejection of system options proves nothing about confinement. Fix the "
      + "builder (or pass a `positiveControl` this home actually declares) before reading this check."
    );
    assert lib.assertMsg (expressible == [ ]) (
      "${name}: this module set has a SYSTEM CHANNEL — the out-of-universe option(s) "
      + "[${lib.concatStringsSep ", " expressible}] are expressible in the home, so a user could "
      + "reach host state directly (ADR-0002). Something in the imports declares them (a freeform "
      + "type, or a NixOS module pulled into the home); remove it. If instead the home is never "
      + "FORCED by `force`, every probe looks expressible — check that `force` reaches the module "
      + "merge (the default is `home.activationPackage.drvPath`)."
    );
    okWitness pkgs name;

  # mkIdentityPostureCheck (issue #35): assert every identity in a repo's OWN roster carries the
  # login-credential posture that repo has chosen (ADR-0019).
  #
  # OPT-IN BY CONSTRUCTION, and that is the whole design. ADR-0019 makes the posture conditional
  # and consumer-owned — a private repo may legitimately ship `$6$` sha512crypt; a public/shared
  # repo wants yescrypt because its hash is world-readable. So `loadIdentity` imposes NO hash
  # policy: baking yescrypt into the loader would impose one repo's public posture on every
  # consumer, including the untrusted roaming single-user flakes the greeter exists for. A repo
  # states its own posture, once, by calling this:
  #
  #     contract.lib.mkIdentityPostureCheck {
  #       inherit pkgs;
  #       identities = map contract.lib.loadIdentity rosterPaths;  # derived, never hardcoded
  #       require = "yescrypt";
  #     }
  #
  # `require` has NO DEFAULT: the contract does not pick a repo's posture, so the caller must say
  # which one it is asserting. Known postures are `credentialPostures` above (ADR-0019's two:
  # `yescrypt`, `libc`); an unknown name is a loud error naming them, since a posture typo must
  # never read as "checked". `identities` is a LIST of loaded identities (`lib.attrValues` an
  # attrset roster) — derive it from the users directory rather than hardcoding it, so a newly
  # added user is covered instead of silently skipped; an empty list is a hard error rather than a
  # vacuous pass.
  mkIdentityPostureCheck =
    {
      identities,
      require,
      pkgs,
      name ? "identity-posture",
    }:
    let
      posture =
        credentialPostures.${require} or (throw (
          "${name}: unknown credential posture '${require}' — known postures are: "
          + "${lib.concatStringsSep ", " (lib.attrNames credentialPostures)} (ADR-0019)."
        ));
      # `loadIdentity` returns the identity.json RAW (the option submodule fills defaults only
      # once the value is assigned to an option), and `hashedPassword` is an OPTIONAL field — so a
      # roster entry may legitimately have no such attribute. Default it to "" here, or the
      # documented call above dies with `attribute 'hashedPassword' missing` instead of this
      # check's named verdict: an absent credential is a posture FAILURE, not a crash.
      hashOf = id: id.hashedPassword or "";
      satisfies = id: lib.any (p: lib.hasPrefix p (hashOf id)) posture.prefixes;
      offenders = lib.filter (id: !(satisfies id)) identities;
      # Name the offender and the algorithm it DOES carry. Only a well-formed `$id$` prefix is
      # echoed (a short alphanumeric algorithm label, never key material) — anything else is
      # reported as unrecognised rather than printed, so a plaintext or otherwise non-crypt field
      # is never quoted into a build log.
      describe =
        id:
        let
          hash = hashOf id;
          matched = builtins.match "\\$([a-zA-Z0-9]{1,6})\\$.*" hash;
          algorithm =
            if hash == "" then
              "no hash"
            else if matched == null then
              "<unrecognised, not a crypt hash>"
            else
              "'$" + lib.head matched + "$'";
        in
        "${id.username or "<identity with no username>"} (${algorithm})";
    in
    assert lib.assertMsg (lib.isList identities) (
      "${name}: `identities` must be a LIST of loaded identities; an attrset roster is passed as "
      + "`lib.attrValues roster`."
    );
    assert lib.assertMsg (identities != [ ]) (
      "${name}: no identities to check — a posture check over an empty roster passes vacuously "
      + "forever. Derive the roster from the users directory (every subdir with an identity.json) "
      + "so a newly added user is covered rather than silently skipped."
    );
    assert lib.assertMsg (offenders == [ ]) (
      "${name}: identity.json credential(s) do not carry the required posture "
      + "${posture.description}: ${lib.concatMapStringsSep ", " describe offenders}. "
      + "Re-hash with `${posture.remedy}` (ADR-0019: the credential travels with the user as "
      + "public data, and repo visibility picks the hash strength)."
    );
    okWitness pkgs name;
}
