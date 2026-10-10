# Trogon.Test

**Trogon.Test is a shared ExUnit toolkit that keeps tests isolated, async-safe, and free of copied helpers.** It collects the fakes, assertions, and case templates that every Elixir project ends up writing in its own `test/support` directory into one versioned Hex package.

**The first release ships `Trogon.Test.Application`, a per-process fake for `Application` itself.** It falls through to the real `Application` module until a test overrides it, and the override belongs to the test process alone, so it reaches the processes that test starts and disappears on its own when the test exits. Later releases add fakes and assertions for other global state as the same need comes up elsewhere.

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

Point the facade at `Trogon.Test.Application` for the test environment:

```elixir
# config/test.exs
config :my_app, MyApp, application: Trogon.Test.Application
```

Every other environment keeps reading `Application`, since the facade only swaps the module when `Trogon.Test.Application` is configured.

### Override env in a test

Alias the module under another name. Aliasing it as `Application` shadows the real module for the rest of that file:

```elixir
defmodule MyApp.BillingTest do
  use ExUnit.Case, async: true

  alias Trogon.Test.Application, as: TestApplication

  test "charges the configured tax rate" do
    TestApplication.put_env(:my_app, :tax_rate, 0.07)
    assert MyApp.Billing.tax_rate() == 0.07
  end
end
```

The override is visible to the test process and to any of its `$callers`, such as a `Task` the test starts, and disappears once the test process exits. No `on_exit` callback is needed to restore the value.

Deep merge onto the current value with `merge_env/3`, instead of replacing it outright:

```elixir
TestApplication.merge_env(:my_app, :feature_flags, beta_search: true)
```

Make a key read as missing, no matter what the real `Application` holds for it, with `delete_env/2`:

```elixir
TestApplication.delete_env(:my_app, :tax_rate)
```

### Allow a process

A process the test starts through `Task.async` or `Task.start` already sees the test's overrides, since `$callers` covers it. A process started another way, a `GenServer` started with `start_link` for instance, does not, until the test allows it:

```elixir
{:ok, worker} = MyApp.Worker.start_link()
TestApplication.allow(worker)
```

`allow/2` also takes a zero-arity function in place of a PID, for a process the test has not started yet at the point it calls `allow/2`.
