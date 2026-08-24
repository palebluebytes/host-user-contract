# Changelog

## [0.1.1](https://github.com/palebluebytes/host-user-contract/compare/host-user-contract-v0.1.0...host-user-contract-v0.1.1) (2026-08-24)


### Documentation

* **research:** survey eval-free parsers for contract.identity.* ([#75](https://github.com/palebluebytes/host-user-contract/issues/75)) ([f129bb8](https://github.com/palebluebytes/host-user-contract/commit/f129bb8e01f64fae0f451894be9e0c4fb259fefb))

## 0.1.0 (2026-08-24)


### ⚠ BREAKING CHANGES

* **contract:** `~/.contract-desktop` is no longer written into any home — a seat that read the file must take the desktop from `contractUsers.<system>.<user>.modeParams.<mode>.desktop`, and a replacement session launcher receives it as its third argument rather than reading the home. Separately, `gmail` is no longer an identity field, so an `identity.json` still carrying it is refused by `loadIdentity` as an unknown key; `name` and `email` are optional now, defaulting to "", which leaves `username` as the only required field, and an identity omitting `name` realizes an account with an empty GECOS.
* **contract:** a second definition of any `contract.users.<u>.identity` field is now an eval error. Neither identity surface carries option defaults, so a hand-assembled account must be handed a complete record — `lib.resolveIdentity` completes a partial one.
* **contract:** `loadIdentity` returns a complete identity record rather than the raw parse. A caller distinguishing "field absent" from "field defaulted" no longer can — nothing in the contract did, and `identitySchema.optional` still names which fields those are.
* **contract:** a home module defining any `contract.identity.*` field is now an eval error. A consumer using `homeModules.default` directly must hand it a complete identity record; `mkContractHome` does this for its callers.
* **contract:** a home reading `config.identity.*` must read `config.contract.identity.*`.
* **contract:** a manifest's `version` is a semver string, not an integer, and compatibility is by major release. Every contractPackage published by an earlier contract must be rebuilt.

### Features

* **contract:** both surfaces HOLD their identity, neither authors it ([e9e8672](https://github.com/palebluebytes/host-user-contract/commit/e9e8672db42614ab8e1380081129b1bfeeca561b))
* **contract:** name the seat VM harness at the flake surface ([2ba2d35](https://github.com/palebluebytes/host-user-contract/commit/2ba2d3535e832be78d9589bf06d8ffd288205385)), closes [#88](https://github.com/palebluebytes/host-user-contract/issues/88)
* **contract:** one owner for how a suite reports its claims ([6ce4cc2](https://github.com/palebluebytes/host-user-contract/commit/6ce4cc222d6a61091850eaab2d823412229dbe04)), closes [#87](https://github.com/palebluebytes/host-user-contract/issues/87)
* **contract:** one owner for how an execution proof says it failed ([2cc1f46](https://github.com/palebluebytes/host-user-contract/commit/2cc1f4607a26c83abbd32fafb34868c237f8d34b)), closes [#91](https://github.com/palebluebytes/host-user-contract/issues/91)
* **contract:** one version, and compatibility by major release ([906bfba](https://github.com/palebluebytes/host-user-contract/commit/906bfbadc4991fb673fd9001f44304437a73d10d))
* **contract:** publish mode parameters in the index, not as home content ([44a067e](https://github.com/palebluebytes/host-user-contract/commit/44a067e3684bec70946d45b30ea47904790cbd46))
* **contract:** the fleet returns its own home-manager CLI adapter ([20a40e7](https://github.com/palebluebytes/host-user-contract/commit/20a40e78cae20d82e1e581ef10cc9f2b7de5ef55)), closes [#89](https://github.com/palebluebytes/host-user-contract/issues/89)
* **contract:** the home holds its identity under `contract.identity` ([0712197](https://github.com/palebluebytes/host-user-contract/commit/071219747e1dc553eaedb6f009c65d92e10721bd))
* **contract:** the identity a home is handed is readOnly ([1a662ad](https://github.com/palebluebytes/host-user-contract/commit/1a662ad78281c287c49c175b27b4005a09a6cb32))
* **contract:** the identity loader returns a complete record ([9d3b7ca](https://github.com/palebluebytes/host-user-contract/commit/9d3b7ca74dcd84755984b2da182427622968f464))


### Bug Fixes

* **contract:** reject a wrong-arity provision call with a named error ([3f9c821](https://github.com/palebluebytes/host-user-contract/commit/3f9c82125c083572d349421d1b621ba769fd3cc6))
* **examples/fleet:** pass the selected mode to the provisioning helper ([eaa52ac](https://github.com/palebluebytes/host-user-contract/commit/eaa52ac9792114ed403287c02c0883c74170cfe8))


### Refactors

* **contract:** hold four load-bearing guard chains apart from their work ([e9d6648](https://github.com/palebluebytes/host-user-contract/commit/e9d66489fd3d0d4bf39552cc9458c9749b82d5d8))
* **contract:** inject the one diagnostic module instead of importing it twice ([30ee9d1](https://github.com/palebluebytes/host-user-contract/commit/30ee9d17977e555ecb83e1f55847723403aba762))
* **contract:** split the bind's two refusals, and rename the split half ([d7df25e](https://github.com/palebluebytes/host-user-contract/commit/d7df25e57ef678d23b158688fa56d703f913765a))
* **examples/users:** lift the fleet's proofs into a checks module ([54740a6](https://github.com/palebluebytes/host-user-contract/commit/54740a6345d27dfd1564d59e8cad4f0d5723ad26)), closes [#86](https://github.com/palebluebytes/host-user-contract/issues/86)
* **examples/users:** report the fleet's three proofs as one ([f27ab82](https://github.com/palebluebytes/host-user-contract/commit/f27ab828f499daf697c39a0147a1d9010e148255)), closes [#91](https://github.com/palebluebytes/host-user-contract/issues/91)


### Documentation

* add an illustrated explainer for the contract's two surfaces ([c83ad83](https://github.com/palebluebytes/host-user-contract/commit/c83ad837fd6616956bf5eed0f12ebb2c3fc7c7e9))
* **adr:** identity is resolved once, and neither surface can author it ([9bbcb00](https://github.com/palebluebytes/host-user-contract/commit/9bbcb00348f32a23e0ce17c9c010e5d29f96c503))
* **adr:** name the reserved privileged groups in 0008 ([b219d0b](https://github.com/palebluebytes/host-user-contract/commit/b219d0bfa0cefab2b7e0b544f9695bc5a135673a))
* **adr:** name the seam's owner in 0022 ([e8d9f89](https://github.com/palebluebytes/host-user-contract/commit/e8d9f891b8fe6ef72c25b8fea5834d6ef918a518))
* **adr:** record 0025, the proofs a consumer runs over its own repo ([9902af6](https://github.com/palebluebytes/host-user-contract/commit/9902af66d5ebd926f85ad1a751de6dac72733b80))
* **adr:** record 0026, one option prefix per party ([509c8b9](https://github.com/palebluebytes/host-user-contract/commit/509c8b9dd57d05c1fb7c8aae91716164730e0a12))
* **adr:** record 0027, a mode need not change home content ([23ee3d6](https://github.com/palebluebytes/host-user-contract/commit/23ee3d697bfa4cd71e1d31df29a0a0d95906eea9))
* **adr:** record why identity cannot be a declared Nix option ([5e61044](https://github.com/palebluebytes/host-user-contract/commit/5e61044a9a05ba7e2cc6382c62822ddd5a0de625))
* **adr:** record why the reference host fleet binds from one source ([2a7927c](https://github.com/palebluebytes/host-user-contract/commit/2a7927c37e9a415b0377712291cc97abb27640b2))
* **adr:** the prefix rule reaches every surface the contract declares ([6e83a5a](https://github.com/palebluebytes/host-user-contract/commit/6e83a5a7f612eca0e2ea5fe00b09fc8cf989fd9d)), closes [#82](https://github.com/palebluebytes/host-user-contract/issues/82)
* **agents:** require the ./ prefix on the fleet check targets ([c8ec1d3](https://github.com/palebluebytes/host-user-contract/commit/c8ec1d390a9ff41129983e105fbc8bc524bb2b32))
* cite the records four modules restate, and fix ADR-0012's manifest example ([2fbd573](https://github.com/palebluebytes/host-user-contract/commit/2fbd573b86919906f89d39626909ca69b6a93991))
* **contract:** cite ADR-0020 from the two runtime evaluators ([ab1fbdd](https://github.com/palebluebytes/host-user-contract/commit/ab1fbddb7b87fd0325c72bf5b53bbb4554fe5873))
* **contract:** cite ADR-0025 from check-kit instead of re-arguing it ([b9d1857](https://github.com/palebluebytes/host-user-contract/commit/b9d185786c9d7637cfd5d6ee8f1b02ecb6d41840))
* **contract:** cite the records greeter.nix restates; drop diagnostics' census ([ab27145](https://github.com/palebluebytes/host-user-contract/commit/ab27145f41e0f1b59913bbc58e07d065ef82cc49))
* **contract:** cite the records lib.nix's consumer surface restates ([44b99cd](https://github.com/palebluebytes/host-user-contract/commit/44b99cdf9455f25938b3d577f705dfaa155a07dc))
* **contract:** cite the records lib.nix's producer surface restates ([9d65e9c](https://github.com/palebluebytes/host-user-contract/commit/9d65e9c61cdb4aaea8aa7a57aed8e0d1fb632e06))
* **contract:** cite the records lib.nix's projections restate ([3290e40](https://github.com/palebluebytes/host-user-contract/commit/3290e40ed4c12c27f789b2c3353e3a1bc6e374f3))
* **contract:** cite the records modules.nix restates ([d100b77](https://github.com/palebluebytes/host-user-contract/commit/d100b77af4f31464f638ebb465d487e8ab3974b9))
* **contract:** cite the records realization.nix restates ([d6f4c45](https://github.com/palebluebytes/host-user-contract/commit/d6f4c45c51f0f662c7b293dbcc1bfe1bd757a1d7))
* **contract:** cite the records the greeter scripts restate ([61758e6](https://github.com/palebluebytes/host-user-contract/commit/61758e6508bbb8976cac10e35edc49381c0f53aa))
* **contract:** cite the records the two registries restate, and drop a dead field ([f134f82](https://github.com/palebluebytes/host-user-contract/commit/f134f825b065d03a6e5a956e18b3a564bb5c1feb))
* **contract:** trim version.nix to what the file is ([4aa7d16](https://github.com/palebluebytes/host-user-contract/commit/4aa7d16673ab87fda30358f23c886cc76b5ed823))
* correct four stale ADR citations and one deleted field ([5e7356a](https://github.com/palebluebytes/host-user-contract/commit/5e7356a445d016a9092353f7eba44d110ef4e89f))
* correct seven stale citations in conformance and examples ([e43f77c](https://github.com/palebluebytes/host-user-contract/commit/e43f77c2f184847cf5a24ba1626b2e1393bb9cd4))
* delete the repo-split capstone runbook ([fb5f998](https://github.com/palebluebytes/host-user-contract/commit/fb5f9982fb92b087840a724d4ec20798a30986f6))
* fix a broken CHANGELOG link and two stale `custom.*` examples ([e6d46fc](https://github.com/palebluebytes/host-user-contract/commit/e6d46fca42dbade2f60852a167e1cc5bc952cef4))
* record ADR-0024; refresh CONTEXT, the ADR index, README and AGENTS ([8b3e831](https://github.com/palebluebytes/host-user-contract/commit/8b3e83129d14aff587980f00a2d4089f2334f747))
