# Write a middleware

A middleware is a plain module implementing `Trogon.Dispatcher.Middleware`.

```elixir
defmodule MyApp.RequireTenant do
  @behaviour Trogon.Dispatcher.Middleware

  alias Trogon.Dispatcher.Context

  defstruct [:default]

  @impl true
  def init(opts), do: %__MODULE__{default: Keyword.fetch!(opts, :default)}

  @impl true
  def call(context, next, %__MODULE__{default: default_tenant}) do
    context
    |> Context.put_private(__MODULE__, context.assigns[:tenant] || default_tenant)
    |> next.()
  end
end
```

Attach it with the `middleware` macro:

```elixir
middleware MyApp.RequireTenant, default: "acme"
```

`init/1` runs once at compile time, so put expensive but static setup there and keep `call/3` doing only
per-dispatch work. See `Trogon.Dispatcher.Middleware` for the full contract on `call/3`'s arguments and
`Trogon.Dispatcher.Context` for its fields.

## Read and write assigns and private

```elixir
Context.assign(context, :locale, "en")
```

```elixir
context = Context.put_private(context, __MODULE__, tenant)
Context.get_private(context, MyApp.RequireTenant)
```

## Attach per-message facts

Static facts about a message, such as the permission it needs, live on the message module, and a middleware reads
them directly:

```elixir
defmodule MyApp.Accounts.RegisterUser do
  @behaviour Trogon.Dispatcher.Handler

  defstruct [:email]

  def timeout, do: :timer.seconds(5)
  def auth_scope, do: "accounts:write"

  @impl true
  def handle_message(%__MODULE__{} = message, _context) do
    {:ok, %MyApp.Accounts.User{email: message.email}}
  end
end

defmodule MyApp.Authorize do
  @behaviour Trogon.Dispatcher.Middleware

  alias Trogon.Dispatcher.Context

  @impl true
  def call(context, next, _opts) do
    scope = context.message.__struct__.auth_scope()

    if MyApp.Auth.permits?(context.actor, scope) do
      next.(context)
    else
      Context.put_response(context, {:error, :forbidden})
    end
  end
end
```

Guard with `function_exported?/3` (after `Code.ensure_loaded?/1`) when only some messages carry the fact.
[Handlers and the context](../explanations/handlers-and-context.md) explains why the library gives these facts no
callback of its own.

## Run a middleware only once per dispatch

A middleware declared at more than one layer runs each time it appears. One with a side effect that must happen
once marks the context and skips itself when the mark is already there:

```elixir
defmodule MyApp.RateLimit do
  @behaviour Trogon.Dispatcher.Middleware

  alias Trogon.Dispatcher.Context

  @impl true
  def call(context, next, options) do
    if Context.get_private(context, __MODULE__) do
      next.(context)
    else
      context
      |> Context.put_private(__MODULE__, :counted)
      |> limit(next, options)
    end
  end

  defp limit(context, next, _options) do
    next.(context)
  end
end
```

## Halt the pipeline

Not calling `next` halts it. Put a response on the context before returning:

```elixir
def call(context, next, _options) do
  case context.actor do
    nil -> Context.put_response(context, {:error, :unauthenticated})
    _actor -> next.(context)
  end
end
```

## Transform the response on the way back

```elixir
def call(context, next, _options) do
  context = next.(context)

  case context.response do
    {:error, %Ecto.Changeset{} = changeset} ->
      Context.put_response(context, {:error, MyApp.Error.from_changeset(changeset)})

    _other ->
      context
  end
end
```

## Annotate the context on the way back

```elixir
def call(context, next, _options) do
  started_at = System.monotonic_time()

  context
  |> next.()
  |> Context.put_private(__MODULE__, System.monotonic_time() - started_at)
end
```

## Dispatch to another dispatcher

Carry the ambient identity forward with `Trogon.Dispatcher.Context.to_dispatch_options/1`:

```elixir
options = Trogon.Dispatcher.Context.to_dispatch_options(context)
MyApp.Billing.Dispatcher.dispatch_message(%ChargeCard{}, options)
```

Set `:message_id` yourself when the nested message carries one:

```elixir
charge = %ChargeCard{}
options = %{Trogon.Dispatcher.Context.to_dispatch_options(context) | message_id: charge.id}
MyApp.Billing.Dispatcher.dispatch_message(charge, options)
```

## Test a middleware in isolation

```elixir
alias Trogon.Dispatcher.Test

context = Test.build_context(%RegisterUser{email: "a@b.c"})

reached = Test.call_middleware(MyApp.RequireTenant, context, options: [default: "acme"])

assert Context.get_private(reached, MyApp.RequireTenant) == "acme"
assert reached.response == :ok
```

See `Trogon.Dispatcher.Test.call_middleware/3` for what it does with `init/1` and `:next`, and the contract it enforces.
