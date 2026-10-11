# Trogon.Dispatcher

**Trogon.Dispatcher is a compile-time command and query dispatcher for Elixir.** In-process, stateless, and synchronous: no processes, no persistence, and no opinion about your domain.

**It gives a host app a single `MyApp.Dispatcher.dispatch_message/2` entry point, built at compile time.** Commands and queries are structs registered with `register_message`, and handlers are plain modules exporting `handle_message/2`. Middleware wraps the pipeline Rack style and deals only in contexts, dispatchers compose into larger dispatchers with `import_dispatcher`, and every dispatch emits a `:telemetry` span.

**Code that routes messages to handlers tends to end up either coupled to an event sourcing framework or scattered across ad-hoc `case` statements.** This library owns the cross-cutting concerns, meaning routing, middleware composition, observability and test tooling, and owns no architecture: there are no events, no aggregates, and no repos. Routing resolves at compile time into direct function clauses, so a duplicate registration, a missing handler, or a dispatcher cycle fails the build rather than a request. Dispatching an unregistered struct returns an error. Every dispatch is a `:telemetry` span, and an optional `Trogon.Dispatcher.OpenTelemetry` integration turns it into a trace; see [Trace with OpenTelemetry](trace-with-opentelemetry.html).

**It is for Elixir teams that want an explicit, observable boundary between their web or worker layer and their domain code.** That suits applications which have outgrown scattered routing but do not want to take on a framework's opinion about how the domain itself is implemented, and teams who need the dispatch boundary to be the one place identity propagation, authorization and tracing are applied.

## Usage

```elixir
defmodule MyApp.Accounts.RegisterUser do
  @behaviour Trogon.Dispatcher.Handler

  defstruct [:email]

  @impl true
  def handle_message(%__MODULE__{} = message, _context) do
    {:ok, %MyApp.Accounts.User{email: message.email}}
  end
end

defmodule MyApp.Accounts.GetUser do
  @behaviour Trogon.Dispatcher.Handler

  defstruct [:id]

  @impl true
  def handle_message(%__MODULE__{} = message, _context) do
    {:ok, MyApp.Accounts.fetch_user!(message.id)}
  end
end

defmodule MyApp.Accounts.Dispatcher do
  use Trogon.Dispatcher

  middleware MyApp.Accounts.RequireTenant

  register_message MyApp.Accounts.RegisterUser, kind: :command
  register_message MyApp.Accounts.GetUser, kind: :query
end

defmodule MyApp.Dispatcher do
  use Trogon.Dispatcher

  middleware MyApp.Authorize

  import_dispatcher MyApp.Accounts.Dispatcher
  import_dispatcher MyApp.Billing.Dispatcher
end
```

```elixir
iex> MyApp.Dispatcher.dispatch_message(%MyApp.Accounts.RegisterUser{email: "a@b.c"})
{:ok, %MyApp.Accounts.User{email: "a@b.c"}}
```

## Documentation

### Tutorials

- [Build an accounts dispatcher](build-an-accounts-dispatcher.html)

### How-to

- [Compose dispatchers](compose-dispatchers.html)
- [Write a middleware](write-middleware.html)
- [Test with Mox](test-with-mox.html)
- [Observe with telemetry](observe-with-telemetry.html)
- [Trace with OpenTelemetry](trace-with-opentelemetry.html)

### Explanations

- [Why wrapping middleware](why-wrapping-middleware.html)
- [Handlers and the context](handlers-and-context.html)
- [The compile-time model](compile-time-model.html)

### References

- [API Reference](api-reference.html)
