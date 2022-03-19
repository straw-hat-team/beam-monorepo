# Explanations

## Enhancing Testing Environments

We publish some `ExUnit.CaseTemplate` as part of the package, we don't have that code to be compiled to production, or
maintain a different package we must do some workaround the limitations problems, for now.

The test support files are under `test/test_support` directory, since the modules is not under `lib` directory, Elixir
will not load this module without importing the file manually. Read more
about [How-to import Test Support files](../how-to-guides/README.md#import-test-support-files).

The Test support files are composed of the following modules:

- `OnePiece.Commanded.TestSupport.CommandHandlerCase` in `test/test_support/command_handler_case.ex`  helpful for testing
  command handler use cases.
