# Trogon.Test

**Trogon.Test is a shared ExUnit toolkit that keeps tests isolated, async-safe, and free of copied helpers.** It collects the mocks, assertions, and case templates that every Elixir project ends up writing in its own `test/support` directory into one versioned Hex package.

**It ships Mox mocks for the global state tests most often need to control, such as the application environment, the clock, timers, and tasks.** Each mock calls the real module through a stub until a test expects a call, and each expected call is recorded so the test asserts afterwards on what it was given. Expectations are owned by the test process, so they reach the processes that test starts and disappear on their own when the test exits.

**Tests that write global state, such as `Application.put_env/3`, cannot run `async: true`, and the `on_exit` that restores the old value races every other test reading the same key while it runs.** Tests that read the real clock or wait on real timers are either vague or slow. Projects work around these by serializing their suites or by copying the same Mox helpers into one `test/support` directory after another, where the copies drift apart. A shared package replaces those workarounds with one tested implementation that a fix reaches through an upgrade.

**This is for teams that maintain more than one Elixir repository and want their test suites to run concurrently without each project rebuilding its own test support.** It pairs with `trogon_credo`'s check for application environment mutation in tests, which flags the same `Application.put_env/3` calls this package replaces.

Depend on `trogon_test` with `only: :test`. Nothing outside the test environment needs it: the facade below calls the real module everywhere else, so `trogon_test` and Mox never ship with your release.

## Wire a facade

Code that calls global state directly cannot be controlled per test. Call it through a module your project compiles in instead, the real module in every environment but test:

```elixir
defmodule MyApp do
  @application Application.compile_env(:my_app, [__MODULE__, :application], Application)
  @date_time Application.compile_env(:my_app, [__MODULE__, :date_time], DateTime)

  defdelegate get_env(app, key, default \\ nil), to: @application
  defdelegate utc_now(), to: @date_time
end
```

and point it at the mocks in `config/test.exs`:

```elixir
config :my_app, MyApp,
  application: Trogon.Test.MockApplication,
  date_time: Trogon.Test.MockDateTime
```

Each `Trogon.Test.Test*` module documents the facade lines and config for its mock, and what its expected calls do.

The `Uniq.UUID` mock and the `:telemetry` assertions are compiled only when your project depends on `:uniq` and `:telemetry`, so `trogon_test` adds neither to your dependencies.

## Expect a call in a test

`use Trogon.Test` next to any case template, or once inside your own `DataCase` `using` block. It aliases and requires every `Test*` helper, verifies every Mox expectation when the test exits, and stubs each mock to call the real module. The `Test` prefix keeps those aliases from shadowing the real modules. Each test then expects the calls it cares about, and asserts on what they were given:

```elixir
defmodule MyApp.BillingTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  test "stamps the invoice with the configured tax rate and the current time" do
    TestApplication.expect_get_env(times: 1, returns: 0.07)
    TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00.000000Z])

    invoice = MyApp.Billing.issue_invoice()

    assert invoice.tax_rate == 0.07
    assert invoice.issued_at == ~U[2026-01-01 00:00:00.000000Z]
    TestApplication.assert_received_get_env(:my_app, :tax_rate)
    TestDateTime.assert_received_utc_now()
    Trogon.Test.assert_empty_mailbox()
  end
end
```

Every `expect_*` function takes `times:`, how many calls it covers, `1` by default, and a call past it raises `Mox.UnexpectedCallError`. An expectation covers every call to its function whatever arguments it is given. Functions with no expectation keep calling the real module through the stub. An expected call rejects arguments of a type the real function never takes, and an `expect_*` given `returns:` rejects a value the real function never returns, so a test cannot pass on a call production would never see.

A mock with an `assert_received_*` macro sends each expected call to the test process, so the macro checks what the code under test passed. Every mock sends under the same `Trogon.Test` tag, so `Trogon.Test.assert_empty_mailbox/0` at the end of the test fails on any call the test did not assert on, whichever mock recorded it.

To make that check run on its own, opt a test module in with `setup {Trogon.Test, :verify_mailbox_on_exit!}` before its tests expect any call. The test then fails when it exits if any recorded call was never taken out by an `assert_received_*` macro. The check runs after the test process is gone, so it counts only those macros: a call consumed with a plain `assert_received/1` still counts as unasserted, and a test that asserts that way ends with `Trogon.Test.assert_empty_mailbox/0` instead.

## Allow a process

A process the test starts through `Task.async` or `Task.start` already sees the test's expectations, since `$callers` covers it. A process started another way, a `GenServer` under a supervisor for instance, does not, until the test allows it on every mock with `Trogon.Test.allow/1`. Pass its pid, or the name it registers under. A name is looked up each time the process calls a mock, so the test can allow a process before it starts:

```elixir
Trogon.Test.allow(MyApp.Worker)
start_supervised!(MyApp.Worker)
```

## Report a run to an AI agent

`Trogon.Test.AIFormatter` writes a compact plain-text report of the run for an AI agent to read, instead of the CLI formatter's output. A run that passes writes one summary line. A failing test writes its location, the assertion or error that failed, the values the assertion compared that its code does not already show, its stacktrace without ExUnit's own frames, and the logs it captured. Run it in place of the CLI formatter, and the report goes to standard output, to read, pipe, or redirect like any other output:

```sh
mix test --formatter Trogon.Test.AIFormatter
```

To keep the terminal output for people and write the report on the side, the module documents how to run it next to the CLI formatter with a `:path`.
