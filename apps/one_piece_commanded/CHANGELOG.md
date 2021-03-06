# Changelog

## Unreleased

## v0.11.1 - 2022-07-21

- Fix register type with a struct with enforce keys in  `OnePiece.Commanded.TypeProvider` module. 

## v0.11.0 - 2022-07-1

- Add `OnePiece.Commanded.Helpers.tracing_from_metadata/1`
- Add `OnePiece.Commanded.Helpers.tracing_from_metadata/2`

## v0.10.1 - 2022-06-28

- Deprecate `OnePiece.Commanded.cast_to/3` (wrong module) and delegate to
  `OnePiece.Commanded.Helpers` instead.
- Add `OnePiece.Commanded.Helpers.cast_to/3`

## v0.10.0 - 2022-06-23

- Add `OnePiece.Commanded.cast_to/3`

## v0.9.1 - 2022-06-22

- Move test support under `lib` directory.

## v0.7.0 - 2022-02-14

- Added `OnePiece.Commanded.Id`
- Deprecated `OnePiece.Commanded.Helpers.generate_uuid/0`. Use
  `OnePiece.Commanded.Id.new/0` instead.

## v0.6.0 - 2022-02-14

- Added `prefix` option to using `OnePiece.Commanded.TypeProvider`
    
  ```elixir
  defmodule MyTypeProvider do
    use OnePiece.Commanded.TypeProvider, prefix: "accounts."
  end
  ```

## v0.5.0 - 2022-02-14

- Added `OnePiece.Commanded.TypeProvider`

## v0.4.0 - 2021-11-25

- Improve documentation

## v0.4.0 - 2021-08-15

- Add `OnePiece.Commanded.Event` module

## v0.3.0 - 2021-08-15

- Fix docs
- Fix version bump

## v0.2.1 - 2021-08-15

- Add test support files

## v0.2.0 - 2021-08-08

- Fix putting aggregate id to command function name

## v0.1.3 - 2021-08-08

- Fix aliases

## v0.1.2 - 2021-08-08

- Fix `__using__` for aggregate, command handler, query handler, and value
  object

## v0.1.1 - 2021-08-08

- Remove dead-code

## v0.1.0 - 2021-08-08

- Initial release
