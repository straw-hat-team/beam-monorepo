# Changelog

## Unreleased

## v1.0.0 - 2024-04-18

### Breaking changes

Fixed all the Credo warnings about using `is_*` predicates outside of guards.

- `OnePiece.Result.is_ok?/1` becomes `OnePiece.Result.ok?/1`
- `OnePiece.Result.is_ok_and?/1` becomes `OnePiece.Result.ok_and?/1`
- `OnePiece.Result.is_err?/1` becomes `OnePiece.Result.err?/1`
- `OnePiece.Result.is_err_and?/1` becomes `OnePiece.Result.err_and?/1`

## v0.4.0 - 2023-04-26

- Added `OnePiece.Result.unwrap/1`.

## v0.3.1 - 2022-09-25

- Fix typespec of `OnePiece.Result.when_err/2`.
- Fix typespec of `OnePiece.Result.when_ok/2`.

## v0.3.1 - 2022-08-15

- Fix typespec of `OnePiece.Result.reject_nil/2`.

## v0.3.0 - 2022-07-29

- Add support for eager value to `OnePiece.Result.map_ok/2`

## v0.2.0 - 2022-07-27

- Add support for eager value to `OnePiece.Result.when_ok/2`

## v0.1.0 - 2022-06-15

- Initial release
