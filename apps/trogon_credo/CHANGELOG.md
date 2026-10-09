# Changelog

## [0.7.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_credo@v0.6.0...trogon_credo@v0.7.0) (2026-10-09)


### Features

* **trogon_credo:** Enforce the dispatcher's contracts at lint time ([#508](https://github.com/straw-hat-team/beam-monorepo/issues/508)) ([7590c80](https://github.com/straw-hat-team/beam-monorepo/commit/7590c8065258861f840451e66b7b8b9e57aca55e))
* **trogon_credo:** Name Oban workers after the action they perform instead of the mechanism running them ([#509](https://github.com/straw-hat-team/beam-monorepo/issues/509)) ([3ffd6b4](https://github.com/straw-hat-team/beam-monorepo/commit/3ffd6b41d2ffc6dff0daec17b68c759a1654d781))

## [0.6.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_credo@v0.5.0...trogon_credo@v0.6.0) (2026-10-09)


### Features

* **trogon_credo:** Keep commands deterministic and processors' non-determinism swappable ([#503](https://github.com/straw-hat-team/beam-monorepo/issues/503)) ([bb8effb](https://github.com/straw-hat-team/beam-monorepo/commit/bb8effb29c4dbef5ca357be0a910f06432adcbf1))
* **trogon_credo:** Keep errors built only by the context that owns them ([#504](https://github.com/straw-hat-team/beam-monorepo/issues/504)) ([2960252](https://github.com/straw-hat-team/beam-monorepo/commit/296025237f8ebecf29e9d201cd5ff91864f1eb99))
* **trogon_credo:** Share Commanded and OpenTelemetry conventions through Credo plugins ([#500](https://github.com/straw-hat-team/beam-monorepo/issues/500)) ([e9a5c40](https://github.com/straw-hat-team/beam-monorepo/commit/e9a5c4098c78c63a9500b0d32e3f4af5f1b55abb))
* **trogon_credo:** Share Ecto conventions through a Credo plugin ([#498](https://github.com/straw-hat-team/beam-monorepo/issues/498)) ([cd1dd88](https://github.com/straw-hat-team/beam-monorepo/commit/cd1dd884b13c2a72a8948a071109f3cda71a9396))
* **trogon_credo:** Share Oban worker conventions through a Credo plugin ([#499](https://github.com/straw-hat-team/beam-monorepo/issues/499)) ([474646a](https://github.com/straw-hat-team/beam-monorepo/commit/474646a71c8edfb98fec20e83be01bd40bd4b2d2))

## [0.5.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_credo@v0.4.0...trogon_credo@v0.5.0) (2026-09-29)


### Features

* **trogon_credo:** Keep the command handler as the only way to change an aggregate's state ([#490](https://github.com/straw-hat-team/beam-monorepo/issues/490)) ([2de4ccb](https://github.com/straw-hat-team/beam-monorepo/commit/2de4ccbc58c22bd370c196c6e8b8952a71f3d17c))

## [0.4.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_credo@v0.3.0...trogon_credo@v0.4.0) (2026-09-24)


### Features

* **trogon_credo:** Make losing OpenTelemetry context across a task its own rule ([#488](https://github.com/straw-hat-team/beam-monorepo/issues/488)) ([1ada5e7](https://github.com/straw-hat-team/beam-monorepo/commit/1ada5e7feed68a9ac075bdfa66030fad0f07a94f))

## [0.3.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_credo@v0.2.0...trogon_credo@v0.3.0) (2026-09-23)


### Features

* **trogon_credo:** Enforce a project's architectural rules without a compiled build ([#469](https://github.com/straw-hat-team/beam-monorepo/issues/469)) ([2eec76b](https://github.com/straw-hat-team/beam-monorepo/commit/2eec76be385db097cf7ff2f2857bb2796720631f))
* **trogon_credo:** Let a boundary cover the Erlang modules a project reaches for ([#485](https://github.com/straw-hat-team/beam-monorepo/issues/485)) ([12849fd](https://github.com/straw-hat-team/beam-monorepo/commit/12849fd233a6269539aeaf1c13fe5c5a9c2e1dee))
* **trogon_credo:** Let a boundary name the namespace its exception belongs to ([#481](https://github.com/straw-hat-team/beam-monorepo/issues/481)) ([b74f9e9](https://github.com/straw-hat-team/beam-monorepo/commit/b74f9e94d11f6878f2d3ae90e65b1c2307e31e2e))
* **trogon_credo:** Let a boundary read a directive that names its targets together ([#482](https://github.com/straw-hat-team/beam-monorepo/issues/482)) ([ce98076](https://github.com/straw-hat-team/beam-monorepo/commit/ce98076b52769f1983ed74013a13087fe0daca18))
* **trogon_credo:** Let a boundary that repeats in every namespace be stated once ([#473](https://github.com/straw-hat-team/beam-monorepo/issues/473)) ([55b6f7f](https://github.com/straw-hat-team/beam-monorepo/commit/55b6f7f1c8b48772167262bea802fea5c9a1fda6))
* **trogon_credo:** Let a forbidden call rule cover a namespace of modules ([#478](https://github.com/straw-hat-team/beam-monorepo/issues/478)) ([606e9ba](https://github.com/straw-hat-team/beam-monorepo/commit/606e9bab5a9c1a5bfa292694bb760f9db57bce1e))
* **trogon_credo:** Let a forbidden call rule keep the one way in it still allows ([#479](https://github.com/straw-hat-team/beam-monorepo/issues/479)) ([5aae4cf](https://github.com/straw-hat-team/beam-monorepo/commit/5aae4cf3f0c34178c14afa3bd9c629335a71fb4e))
* **trogon_credo:** Let a forbidden call rule object to one way of calling a function ([#480](https://github.com/straw-hat-team/beam-monorepo/issues/480)) ([92d34ff](https://github.com/straw-hat-team/beam-monorepo/commit/92d34ff5a67113cc81fac6ae7af830a99f086266))
* **trogon_credo:** Let a project say a module must exist, or must be the only one of its kind ([#484](https://github.com/straw-hat-team/beam-monorepo/issues/484)) ([727640a](https://github.com/straw-hat-team/beam-monorepo/commit/727640a17f962c9125e7ae6fb630969b7a111d9b))
* **trogon_credo:** Let a project state which applications may depend on which ([#483](https://github.com/straw-hat-team/beam-monorepo/issues/483)) ([d216729](https://github.com/straw-hat-team/beam-monorepo/commit/d2167299184e5f26bb42145d449ceac0ae2636b1))
* **trogon_credo:** Let a rule forbid every call to a module, Erlang ones included ([#474](https://github.com/straw-hat-team/beam-monorepo/issues/474)) ([5d7d34e](https://github.com/straw-hat-team/beam-monorepo/commit/5d7d34ec75b47358ddc6e59ed358e0fbe997ac77))

## [0.2.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_credo@v0.1.0...trogon_credo@v0.2.0) (2026-09-21)


### Features

* **trogon_credo:** Let a project fit these checks to conventions it already has ([#467](https://github.com/straw-hat-team/beam-monorepo/issues/467)) ([0d9bd7c](https://github.com/straw-hat-team/beam-monorepo/commit/0d9bd7c150324f3e89b1ce566e82072f6e681f0f))

## [0.1.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_credo@v0.0.1...trogon_credo@v0.1.0) (2026-09-16)


### Features

* **trogon_credo:** Add package for sharing custom credo checks ([#456](https://github.com/straw-hat-team/beam-monorepo/issues/456)) ([57e5851](https://github.com/straw-hat-team/beam-monorepo/commit/57e5851bfc6bb58384d835cb8ad19ca9fb42907f))
* **trogon_credo:** Forbid bringing a module in with use ([#460](https://github.com/straw-hat-team/beam-monorepo/issues/460)) ([7a2838f](https://github.com/straw-hat-team/beam-monorepo/commit/7a2838fc8f5216289194daf744546790292384bb))
* **trogon_credo:** Let a project prefer named functions over anonymous ones ([#461](https://github.com/straw-hat-team/beam-monorepo/issues/461)) ([2a9f091](https://github.com/straw-hat-team/beam-monorepo/commit/2a9f09154183917556dac50ff24582cd36952ac1))

## Changelog
