# Trogon.Test

**Trogon.Test is a shared ExUnit toolkit that keeps tests isolated, async-safe, and free of copied helpers.** It collects the mocks, assertions, and case templates that every Elixir project ends up writing in its own `test/support` directory into one versioned Hex package.

**The first release ships Mox mocks for the global state tests most often need to control: `Trogon.Test.TestApplication` for the application environment and `Trogon.Test.TestDateTime` for the clock.** Each mock reads the real module through a stub until a test expects a call with `times:` and `returns:`, and each expected call is recorded so the test asserts afterwards on what it was given. Expectations are owned by the test process, so they reach the processes that test starts and disappear on their own when the test exits. Later releases add mocks and assertions for other global state as the same need comes up elsewhere.

**Tests that write global state, such as `Application.put_env/3`, cannot run `async: true`, and the `on_exit` that restores the old value races every other test reading the same key while it runs.** Tests that read the real clock can only assert on the shape of a timestamp, never its value. Projects work around both by serializing their suites or by copying the same Mox helpers into one `test/support` directory after another, where the copies drift apart. A shared package replaces those workarounds with one tested implementation that a fix reaches through an upgrade.

**This is for teams that maintain more than one Elixir repository and want their test suites to run concurrently without each project rebuilding its own test support.** It pairs with `trogon_credo`'s check for application environment mutation in tests, which flags the same `Application.put_env/3` calls this package replaces.

## How-to

### Install trogon_test

Add it to your test dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:trogon_test, "~> 0.1", only: :test}
  ]
end
```

Keep it `only: :test`. Nothing outside the test environment needs it: each facade below reads the real module everywhere else, so `trogon_test` and Mox never ship with your release.

### Wire a facade

Code that calls `Application` or `DateTime` directly cannot be controlled per test. Call them through a module your project compiles in instead, the real module in every environment but test:

```elixir
defmodule MyApp.Config do
  @application Application.compile_env(:my_app, [__MODULE__, :application], Application)

  defdelegate get_env(app, key, default \\ nil), to: @application
end

defmodule MyApp.Clock do
  @date_time Application.compile_env(:my_app, [__MODULE__, :date_time], DateTime)

  defdelegate utc_now(), to: @date_time
end
```

Call the facade from the rest of the project wherever it would otherwise call `Application.get_env/2,3` or `DateTime.utc_now/0`.

### Configure config/test.exs

Point each facade at its mock for the test environment:

```elixir
# config/test.exs
config :my_app, MyApp.Config, application: Trogon.Test.TestApplication.MockApplication
config :my_app, MyApp.Clock, date_time: Trogon.Test.TestDateTime.MockDateTime
```

Every other environment keeps calling the real modules, since the facade only swaps the module when the mock is configured.

### Expect a call in a test

Stub the mock in `setup`, expect the calls the test cares about with what they return, then assert on what they were given. Require each module for its `assert_received_*` macros. The `Test` prefix keeps an alias from shadowing the real `Application` or `DateTime`:

```elixir
defmodule MyApp.BillingTest do
  use ExUnit.Case, async: true

  import Mox

  alias Trogon.Test.TestApplication
  alias Trogon.Test.TestDateTime

  require TestApplication
  require TestDateTime

  setup :verify_on_exit!
  setup {TestApplication, :stub}
  setup {TestDateTime, :stub}

  test "stamps the invoice with the configured tax rate and the current time" do
    TestApplication.expect_get_env(times: 1, returns: 0.07)
    TestDateTime.expect_utc_now(times: 1, returns: ~U[2026-01-01 00:00:00Z])

    invoice = MyApp.Billing.issue_invoice()

    assert invoice.tax_rate == 0.07
    assert invoice.issued_at == ~U[2026-01-01 00:00:00Z]
    TestApplication.assert_received_get_env(:my_app, :tax_rate)
    TestDateTime.assert_received_utc_now()
  end
end
```

Every `expect_*` function takes `returns:`, the value the call returns, and `times:`, how many calls it covers, `1` by default. An expectation covers every call to its function whatever arguments it is given, and a call past `times:` raises `Mox.UnexpectedCallError`. Functions with no expectation keep calling the real module through the stub.

Each expected call is sent to the test process, so the matching `assert_received_*` macro checks what the code under test passed. No `on_exit` callback is needed, since nothing outside the test process changed.

### Allow a process

A process the test starts through `Task.async` or `Task.start` already sees the test's expectations, since `$callers` covers it. A process started another way, a `GenServer` started with `start_link` for instance, does not, until the test allows it with `Mox.allow/3` on each mock it calls:

```elixir
{:ok, worker} = MyApp.Worker.start_link()
Mox.allow(Trogon.Test.TestApplication.MockApplication, self(), worker)
Mox.allow(Trogon.Test.TestDateTime.MockDateTime, self(), worker)
```
