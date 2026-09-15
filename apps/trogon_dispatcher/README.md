# Trogon.Dispatcher

**An in-process, stateless, synchronous command and query dispatcher for Elixir, with compile-time routing, composable wrapping middleware, and `:telemetry` spans.**

**Trogon.Dispatcher gives a host app a `MyApp.dispatch_command/2` entry point built at compile time. Commands and queries are structs registered with `register_command`, handlers are plain modules exporting `handle_command/2`, middleware wraps the pipeline Rack style with `call(context, next, options)` and deals in contexts only, and dispatchers compose into larger dispatchers with `import_dispatcher`. Every dispatch emits a `:telemetry` span carrying the command module, the kind, the dispatcher, and the dispatcher that registered the command.**

**Application code that routes messages to handlers usually ends up either coupled to a full event-sourcing framework or scattered across ad-hoc `case` statements. Trogon.Dispatcher owns the cross-cutting concerns (routing, middleware composition, observability, test tooling) and owns no architecture: there are no events, no aggregates, no repos, and no processes. Routing is resolved at compile time into direct function clauses, so a dispatch is a pattern match and a chain of calls.**

**Trogon.Dispatcher is for Elixir teams that want an explicit, observable boundary between the web or worker layer and their domain code, without adopting an opinion about how that domain is implemented.**

## Installation

```elixir
def deps do
  [
    {:trogon_dispatcher, "~> 0.1"}
  ]
end
```

## Usage

```elixir
defmodule MyApp.Accounts.RegisterUser do
  defstruct [:email]

  def handle_command(%__MODULE__{} = command, _context) do
    {:ok, %MyApp.Accounts.User{email: command.email}}
  end
end

defmodule MyApp.Accounts.Dispatcher do
  use Trogon.Dispatcher

  middleware MyApp.Accounts.RequireTenant

  register_command MyApp.Accounts.RegisterUser, kind: :command
  register_command MyApp.Accounts.GetUser, kind: :query
end

defmodule MyApp.Dispatcher do
  use Trogon.Dispatcher, telemetry_prefix: [:my_app, :dispatcher]

  middleware MyApp.Authorize

  import_dispatcher MyApp.Accounts.Dispatcher
  import_dispatcher MyApp.Billing.Dispatcher
end
```

```elixir
iex> MyApp.Dispatcher.dispatch_command(%MyApp.Accounts.RegisterUser{email: "a@b.c"})
{:ok, %MyApp.Accounts.User{email: "a@b.c"}}
```

## Documentation

### How-to

- [Compose dispatchers](compose-dispatchers.html)
- [Write a middleware](write-middleware.html)
- [Test with Mox](test-with-mox.html)
- [Observe with telemetry](observe-with-telemetry.html)

### Explanations

- [Why wrapping middleware](why-wrapping-middleware.html)
- [The compile-time model](compile-time-model.html)

### References

- [The response contract](response-contract.html)
- [API Reference](api-reference.html)
