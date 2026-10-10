# Trogon.Test

**Trogon.Test is a shared ExUnit toolkit that keeps tests isolated, async-safe, and free of copied helpers.** It collects the fakes, assertions, and case templates that every Elixir project ends up writing in its own `test/support` directory into one versioned Hex package.

**The first release ships `Trogon.Test.Application`, a Mox mock for `Application` itself.** Its stub reads the real `Application` module until a test expects a read with `times:` and `returns:`, and asserts afterwards on the app and key the read was given. The expectation is owned by the test process, so it reaches the processes that test starts and disappears on its own when the test exits. Later releases add mocks and assertions for other global state as the same need comes up elsewhere.

**Tests that write global state, such as `Application.put_env/3`, cannot run `async: true`, and the `on_exit` that restores the old value races every other test reading the same key while it runs.** Projects work around this by serializing their suites or by copying the same stub into one `test/support` directory after another, where the copies drift apart. A shared package replaces both workarounds with one tested implementation that a fix reaches through an upgrade.

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

Keep it `only: :test`. Nothing outside the test environment needs it: the facade below reads `Application` everywhere else, so `trogon_test` and Mox never ship with your release.

### Wire the facade

Code that reads `Application` directly cannot be overridden per test. Read it through a module your project compiles in instead, `Application` itself in every environment but test:

```elixir
defmodule MyApp.Config do
  @application Application.compile_env(:my_app, [MyApp, :application], Application)

  defdelegate get_env(app, key, default \\ nil), to: @application
end
```

Call `MyApp.Config.get_env/2,3` from the rest of the project wherever it would otherwise call `Application.get_env/2,3`.

### Configure config/test.exs

Point the facade at the mock for the test environment:

```elixir
# config/test.exs
config :my_app, MyApp, application: Trogon.Test.Application.Mock
```

Every other environment keeps reading `Application`, since the facade only swaps the module when the mock is configured.

### Expect a read in a test

Stub the mock in `setup`, expect the reads the test cares about with what they return, then assert on what they were given. Alias the module under another name, since aliasing it as `Application` shadows the real module for the rest of that file:

```elixir
defmodule MyApp.BillingTest do
  use ExUnit.Case, async: true

  import Mox

  alias Trogon.Test.Application, as: TestApplication

  require TestApplication

  setup :verify_on_exit!
  setup {TestApplication, :stub}

  test "charges the configured tax rate" do
    TestApplication.expect_get_env(times: 1, returns: 0.07)

    tax_rate = MyApp.Billing.tax_rate()

    assert tax_rate == 0.07
    TestApplication.assert_received_get_env(:my_app, :tax_rate)
  end
end
```

`expect_get_env/1`, `expect_fetch_env/1`, `expect_fetch_env!/1`, and `expect_get_all_env/1` each take `returns:`, the value the call returns, and `times:`, how many calls it covers, `1` by default. An expectation covers every call to its function whatever key it reads, and a call past `times:` raises `Mox.UnexpectedCallError`. Functions with no expectation keep reading the real `Application`.

Each expected call is sent to the test process, so the matching `assert_received_*` macro checks what the code under test read, once the test module requires `Trogon.Test.Application`. No `on_exit` callback is needed, since nothing outside the test process changed.

### Allow a process

A process the test starts through `Task.async` or `Task.start` already sees the test's expectations, since `$callers` covers it. A process started another way, a `GenServer` started with `start_link` for instance, does not, until the test allows it with `Mox.allow/3`:

```elixir
{:ok, worker} = MyApp.Worker.start_link()
Mox.allow(Trogon.Test.Application.Mock, self(), worker)
```
