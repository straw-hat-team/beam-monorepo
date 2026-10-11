# Trogon.Test

**Trogon.Test is a shared ExUnit toolkit that keeps tests isolated, async-safe, and free of copied helpers.** It collects the mocks, assertions, and case templates that every Elixir project ends up writing in its own `test/support` directory into one versioned Hex package.

**The first release ships Mox mocks for the global state tests most often need to control: `Trogon.Test.TestApplication` for the application environment, `Trogon.Test.TestDateTime` for the clock, and `Trogon.Test.TestProcess` for timers and sleeps.** Each mock reads the real module through a stub until a test expects a call with `times:` and `returns:`, and each expected call is recorded so the test asserts afterwards on what it was given. Expectations are owned by the test process, so they reach the processes that test starts and disappear on their own when the test exits. Later releases add mocks and assertions for other global state as the same need comes up elsewhere.

**Tests that write global state, such as `Application.put_env/3`, cannot run `async: true`, and the `on_exit` that restores the old value races every other test reading the same key while it runs.** Tests that read the real clock can only assert on the shape of a timestamp, never its value. Tests of code that schedules a message with `Process.send_after/4` or calls `Process.sleep/1` either wait for the timer or race it. Projects work around these by serializing their suites or by copying the same Mox helpers into one `test/support` directory after another, where the copies drift apart. A shared package replaces those workarounds with one tested implementation that a fix reaches through an upgrade.

**This is for teams that maintain more than one Elixir repository and want their test suites to run concurrently without each project rebuilding its own test support.** It pairs with `trogon_credo`'s check for application environment mutation in tests, which flags the same `Application.put_env/3` calls this package replaces.

Add it to your test dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trogon_test, "~> 0.1", only: :test}
  ]
end
```

Keep it `only: :test`. Nothing outside the test environment needs it: each facade below reads the real module everywhere else, so `trogon_test` and Mox never ship with your release.

## Wire a facade

Code that calls `Application`, `DateTime`, or `Process` directly cannot be controlled per test. Call them through a module your project compiles in instead, the real module in every environment but test:

```elixir
defmodule MyApp.Config do
  @application Application.compile_env(:my_app, [__MODULE__, :application], Application)

  defdelegate get_env(app, key, default \\ nil), to: @application
end

defmodule MyApp.Clock do
  @date_time Application.compile_env(:my_app, [__MODULE__, :date_time], DateTime)

  defdelegate utc_now(), to: @date_time
end

defmodule MyApp.Timer do
  @process Application.compile_env(:my_app, [__MODULE__, :process], Process)

  defdelegate send_after(dest, msg, time, opts \\ []), to: @process
  defdelegate sleep(timeout), to: @process
end
```

Call the facade from the rest of the project wherever it would otherwise call `Application.get_env/2,3`, `DateTime.utc_now/0`, `Process.send_after/3,4`, or `Process.sleep/1`.

## Configure config/test.exs

Point each facade at its mock for the test environment:

```elixir
# config/test.exs
config :my_app, MyApp.Config, application: Trogon.Test.MockApplication
config :my_app, MyApp.Clock, date_time: Trogon.Test.MockDateTime
config :my_app, MyApp.Timer, process: Trogon.Test.MockProcess
```

Every other environment keeps calling the real modules, since the facade only swaps the module when the mock is configured.

## Expect a call in a test

`use Trogon.Test` next to any case template, or once inside your own `DataCase` `using` block. It aliases and requires `TestApplication`, `TestDateTime`, and `TestProcess`, verifies every Mox expectation when the test exits, and stubs each mock to call the real module. The `Test` prefix keeps those aliases from shadowing the real `Application`, `DateTime`, or `Process`. Each test then expects the calls it cares about with what they return, and asserts on what they were given:

```elixir
defmodule MyApp.BillingTest do
  use ExUnit.Case, async: true
  use Trogon.Test

  test "stamps the invoice with the configured tax rate and the current time" do
    TestApplication.expect_get_env(times: 1, returns: 0.07)
    TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

    invoice = MyApp.Billing.issue_invoice()

    assert invoice.tax_rate == 0.07
    assert invoice.issued_at == ~U[2026-01-01 00:00:00Z]
    TestApplication.assert_received_get_env(:my_app, :tax_rate)
    TestDateTime.assert_received_utc_now()
    Trogon.Test.assert_empty_mailbox()
  end
end
```

Every `expect_*` function takes `returns:`, the value the call returns, and `times:`, how many calls it covers, `1` by default. An expectation covers every call to its function whatever arguments it is given, and a call past `times:` raises `Mox.UnexpectedCallError`. Functions with no expectation keep calling the real module through the stub. An expected call still rejects the arguments the real function rejects, raising the same exception, and `expect_*` rejects a `returns:` the real function never returns, so a test cannot pass on a call that would crash or misbehave in production. `TestProcess.expect_send_after/1` never schedules the message and defaults `returns:` to a new reference, so the test sends the message itself when it wants the timer to fire. `TestProcess.expect_sleep/1` takes only `times:` and returns `:ok` without sleeping.

Each expected call is sent to the test process, so the matching `assert_received_*` macro checks what the code under test passed. Every mock sends under the same `Trogon.Test` tag, so `Trogon.Test.assert_empty_mailbox/0` at the end of the test fails on any call the test did not assert on, whichever mock recorded it. No `on_exit` callback is needed, since nothing outside the test process changed.

## Allow a process

A process the test starts through `Task.async` or `Task.start` already sees the test's expectations, since `$callers` covers it. A process started another way, a `GenServer` under a supervisor for instance, does not, until the test allows it on every mock with `Trogon.Test.allow/1`. Pass its pid, or the name it registers under. A name is looked up each time the process calls a mock, so the test can allow a process before it starts:

```elixir
Trogon.Test.allow(MyApp.Worker)
start_supervised!(MyApp.Worker)
```
