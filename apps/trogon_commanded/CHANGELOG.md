# Changelog

## Unreleased

## [1.0.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.39.0...trogon_commanded@v1.0.0) (2026-04-30)


### ⚠ BREAKING CHANGES

* **trogon_commanded:** clean up dead code and stale config before 1.0 ([#362](https://github.com/straw-hat-team/beam-monorepo/issues/362))
* **trogon_commanded:** remove ObjectId in favor of trogon_object_id ([#361](https://github.com/straw-hat-team/beam-monorepo/issues/361))

### Features

* **trogon_proto:** Support shared error contracts ([#352](https://github.com/straw-hat-team/beam-monorepo/issues/352)) ([101a1f7](https://github.com/straw-hat-team/beam-monorepo/commit/101a1f76ee2cad48f4ada1341204144116b959d1))


### Bug Fixes

* **trogon_commanded:** Clean up dead code and stale config before 1.0 ([#362](https://github.com/straw-hat-team/beam-monorepo/issues/362)) ([9280904](https://github.com/straw-hat-team/beam-monorepo/commit/9280904e83b6f72f8d7613f3e5d189e2c83a1bdd))
* **trogon_commanded:** Remove ObjectId in favor of trogon_object_id ([#361](https://github.com/straw-hat-team/beam-monorepo/issues/361)) ([fe2f8ae](https://github.com/straw-hat-team/beam-monorepo/commit/fe2f8aee4acf0366a072bf9aad16726de0faed4d))

## [0.39.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.38.1...trogon_commanded@v0.39.0) (2026-04-27)


### Features

* **trogon_commanded:** Support proto-driven enums ([#350](https://github.com/straw-hat-team/beam-monorepo/issues/350)) ([cee36fd](https://github.com/straw-hat-team/beam-monorepo/commit/cee36fdd7da75608c582291b935b9ec74379072e))

## [0.38.1](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.38.0...trogon_commanded@v0.38.1) (2026-03-14)


### Bug Fixes

* Make Process module configurable in ConsistencyPolicy ([#337](https://github.com/straw-hat-team/beam-monorepo/issues/337)) ([f52993c](https://github.com/straw-hat-team/beam-monorepo/commit/f52993c9cb8c30f102d6a3f1c216058686b40591))

## [0.38.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.37.0...trogon_commanded@v0.38.0) (2026-03-14)


### Features

* **trogon_commanded:** Add ConsistencyPolicy ([#336](https://github.com/straw-hat-team/beam-monorepo/issues/336)) ([dd2992c](https://github.com/straw-hat-team/beam-monorepo/commit/dd2992c08bc4fafbb07dcbaa0c607545d3f01a66))
* **trogon_proto:** Bump trogon-proto BSR module to v0.8.0 ([#333](https://github.com/straw-hat-team/beam-monorepo/issues/333)) ([ba6ca27](https://github.com/straw-hat-team/beam-monorepo/commit/ba6ca277dcf031642b7beda4f9e79d09bd1fe72f))

## [0.37.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.36.1...trogon_commanded@v0.37.0) (2026-02-15)


### Features

* **trogon_commanded:** Add is_object_id/1 guard ([#329](https://github.com/straw-hat-team/beam-monorepo/issues/329)) ([96e212d](https://github.com/straw-hat-team/beam-monorepo/commit/96e212d1066530ce62787670c44a9f96989e3041))

## [0.36.1](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.36.0...trogon_commanded@v0.36.1) (2026-02-14)


### Bug Fixes

* **trogon_commanded:** Error handling in ObjectId cast function ([#327](https://github.com/straw-hat-team/beam-monorepo/issues/327)) ([0c8a771](https://github.com/straw-hat-team/beam-monorepo/commit/0c8a7711d77c66850631858caff6314c172f701d))

## [0.36.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.35.1...trogon_commanded@v0.36.0) (2026-02-12)


### Features

* **trogon_commanded:** Support proto-driven identity_prefix ([#324](https://github.com/straw-hat-team/beam-monorepo/issues/324)) ([df7bc76](https://github.com/straw-hat-team/beam-monorepo/commit/df7bc76013d314aaf63e8074e62d0ec96a1411e7))
* **trogon_proto:** Bump trogon-proto BSR module to v0.7.0 ([#323](https://github.com/straw-hat-team/beam-monorepo/issues/323)) ([caf9eea](https://github.com/straw-hat-team/beam-monorepo/commit/caf9eea94ae284e653e934d3ae98cd7afeea114a))

## [0.35.1](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.35.0...trogon_commanded@v0.35.1) (2026-02-12)


### Bug Fixes

* **trogon_commanded:** Validate ObjectId values in new/1 and add new!/1 ([#321](https://github.com/straw-hat-team/beam-monorepo/issues/321)) ([d74213e](https://github.com/straw-hat-team/beam-monorepo/commit/d74213e3a6710414a57bb5347f076133a755f349))

## [0.35.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.34.0...trogon_commanded@v0.35.0) (2026-02-11)


### Features

* **trogon_commanded:** Add proto: option to ObjectId ([#313](https://github.com/straw-hat-team/beam-monorepo/issues/313)) ([aa8e503](https://github.com/straw-hat-team/beam-monorepo/commit/aa8e503b68d936e0fdf3f6a4d0e9ca90d4f6d4d7))

## [0.34.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.33.0...trogon_commanded@v0.34.0) (2026-01-22)


### Features

* **trogon_commanded:** Add format validation for ObjectId ([#300](https://github.com/straw-hat-team/beam-monorepo/issues/300)) ([4411b74](https://github.com/straw-hat-team/beam-monorepo/commit/4411b74f69ebfadb078db666e7d3ede6bd00b96d))

## [0.33.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.32.0...trogon_commanded@v0.33.0) (2026-01-15)


### Features

* **trogon_commanded:** Add parse! function for ObjectId and UnionObjectId ([#297](https://github.com/straw-hat-team/beam-monorepo/issues/297)) ([7067fba](https://github.com/straw-hat-team/beam-monorepo/commit/7067fba405a2356916ca988e79ef648ed90fa47c))

## [0.32.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.31.0...trogon_commanded@v0.32.0) (2026-01-15)


### Features

* **trogon_commanded:** Add UnionObjectId macro for union types ([#295](https://github.com/straw-hat-team/beam-monorepo/issues/295)) ([9630ae5](https://github.com/straw-hat-team/beam-monorepo/commit/9630ae56d0d87c68d9d3097d768f952719ec682a))

## [0.31.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.30.0...trogon_commanded@v0.31.0) (2026-01-12)


### Features

* **trogon_commanded:** Add to_storage/1 ([#289](https://github.com/straw-hat-team/beam-monorepo/issues/289)) ([83aa85c](https://github.com/straw-hat-team/beam-monorepo/commit/83aa85c161783f0d8c9adbaa349523c3ca6f2d2f))

## [0.30.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.29.0...trogon_commanded@v0.30.0) (2026-01-12)


### Features

* **trogon_commanded:** Add object id ([#287](https://github.com/straw-hat-team/beam-monorepo/issues/287)) ([a45bf21](https://github.com/straw-hat-team/beam-monorepo/commit/a45bf21a5f0ddb55cd5b27ac67d9c3745160f059))

## [0.29.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.28.1...trogon_commanded@v0.29.0) (2026-01-10)


### Features

* **trogon_commanded:** Add type provider Protobuf message registration directly ([#284](https://github.com/straw-hat-team/beam-monorepo/issues/284)) ([f6b243e](https://github.com/straw-hat-team/beam-monorepo/commit/f6b243e31c9926d5c30bd82af4efcac474702651))


## [0.28.1](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.28.0...trogon_commanded@v0.28.1) (2025-11-23)


### Bug Fixes

* **trogon_commanded:** Use fully qualified module name ([#253](https://github.com/straw-hat-team/beam-monorepo/issues/253)) ([8ef35a5](https://github.com/straw-hat-team/beam-monorepo/commit/8ef35a5fc1766273c35858286c887be670dbf311))

## [0.28.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.27.0...trogon_commanded@v0.28.0) (2025-09-26)


### Features

* **trogon_commanded:** Expose new and new! from value object module ([#237](https://github.com/straw-hat-team/beam-monorepo/issues/237)) ([cd02081](https://github.com/straw-hat-team/beam-monorepo/commit/cd0208185fcb604ddc500d43104fdfe4fdeaa239))

## [0.27.0](https://github.com/straw-hat-team/beam-monorepo/compare/trogon_commanded@v0.26.0...trogon_commanded@v0.27.0) (2025-09-07)


### Features

* **trogon_commanded:** Add polymorphic embed support for value objects ([#230](https://github.com/straw-hat-team/beam-monorepo/issues/230)) ([29960ca](https://github.com/straw-hat-team/beam-monorepo/commit/29960caa3081be76438402a3bf3ef77f6eaa1c74))

## v0.26.0 - 2025-06-27

- Initial release
