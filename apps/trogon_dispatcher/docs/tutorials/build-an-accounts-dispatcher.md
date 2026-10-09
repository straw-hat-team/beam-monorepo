# Build an accounts dispatcher

In this tutorial you build a small accounts boundary: two commands, their handlers, an authorization policy, a
multi-factor check that only one command asks for, and the dispatcher that wires them together.

You need a Mix project with `{:trogon_dispatcher, "~> 0.1"}` in its dependencies.

## Define the messages

A message is a struct. Facts that belong to the message, such as the permission it needs, are plain functions on the
same module. Create `lib/my_app/accounts/messages.ex`:

```elixir
defmodule MyApp.Accounts.User do
  defstruct [:id, :email]
end

defmodule MyApp.Accounts.RegisterUser do
  defstruct [:email]

  def auth_scope, do: "accounts:write"
end

defmodule MyApp.Accounts.DeleteAccount do
  defstruct [:user_id]

  def auth_scope, do: "accounts:delete"
  def requires_mfa?, do: true
end
```

`DeleteAccount` says it needs multi-factor authentication. `RegisterUser` says nothing about it, and that is fine.

## Write the handlers

A handler does the work and nothing else. Match the message struct in the function head. Create
`lib/my_app/accounts/handlers.ex`:

```elixir
defmodule MyApp.Accounts.RegisterUserHandler do
  @behaviour Trogon.Dispatcher.Handler

  alias MyApp.Accounts.RegisterUser
  alias MyApp.Accounts.User

  @impl true
  def handle_message(%RegisterUser{email: email}, _context) do
    {:ok, %User{id: System.unique_integer([:positive]), email: email}}
  end
end

defmodule MyApp.Accounts.DeleteAccountHandler do
  @behaviour Trogon.Dispatcher.Handler

  alias MyApp.Accounts.DeleteAccount
  alias MyApp.Accounts.User

  @impl true
  def handle_message(%DeleteAccount{user_id: user_id}, _context) do
    {:ok, %User{id: user_id}}
  end
end
```

## Write the middleware

Middleware applies a policy to every message and reads the facts from the message module. Create
`lib/my_app/middleware.ex`:

```elixir
defmodule MyApp.Policy do
  def allowed?(%{scopes: scopes}, scope), do: scope in scopes
  def allowed?(_actor, _scope), do: false
end

defmodule MyApp.Authorize do
  @behaviour Trogon.Dispatcher.Middleware

  alias Trogon.Dispatcher.Context

  defstruct [:policy]

  @impl true
  def init(opts), do: %__MODULE__{policy: Keyword.fetch!(opts, :policy)}

  @impl true
  def call(%Context{message: %message_mod{}} = context, next, %__MODULE__{policy: policy}) do
    if policy.allowed?(context.actor, message_mod.auth_scope()) do
      next.(context)
    else
      Context.put_response(context, {:error, :forbidden})
    end
  end
end

defmodule MyApp.RequireMFA do
  @behaviour Trogon.Dispatcher.Middleware

  alias Trogon.Dispatcher.Context

  @impl true
  def call(%Context{message: %message_mod{}} = context, next, _options) do
    if requires_mfa?(message_mod) and not mfa_verified?(context.actor) do
      Context.put_response(context, {:error, :mfa_required})
    else
      next.(context)
    end
  end

  defp requires_mfa?(message_mod) do
    Code.ensure_loaded?(message_mod) and function_exported?(message_mod, :requires_mfa?, 0) and
      message_mod.requires_mfa?()
  end

  defp mfa_verified?(%{mfa_verified?: true}), do: true
  defp mfa_verified?(_actor), do: false
end
```

`MyApp.Authorize` turns its options into a struct in `init/1`, and `call/3` receives that struct. `MyApp.RequireMFA`
needs no options, so it has no `init/1`.

Not calling `next` is how a middleware stops the dispatch. It puts a response on the context instead.

## Wire the dispatchers

The accounts dispatcher registers the messages. The application dispatcher adds the policies and imports it. Create
`lib/my_app/dispatcher.ex`:

```elixir
defmodule MyApp.Accounts.Dispatcher do
  use Trogon.Dispatcher

  alias MyApp.Accounts

  register_message Accounts.RegisterUser, kind: :command, to: Accounts.RegisterUserHandler
  register_message Accounts.DeleteAccount, kind: :command, to: Accounts.DeleteAccountHandler
end

defmodule MyApp.Dispatcher do
  use Trogon.Dispatcher

  middleware MyApp.Authorize, policy: MyApp.Policy
  middleware MyApp.RequireMFA

  import_dispatcher MyApp.Accounts.Dispatcher
end
```

Every message `MyApp.Dispatcher` handles runs `MyApp.Authorize`, then `MyApp.RequireMFA`, then its handler.

## Dispatch

Start `iex -S mix` and dispatch as an administrator who has not verified a second factor:

```elixir
iex> alias MyApp.Accounts.{DeleteAccount, RegisterUser}
iex> alias Trogon.Dispatcher.DispatchOptions
iex> admin = %{id: 1, scopes: ["accounts:write", "accounts:delete"], mfa_verified?: false}
iex> MyApp.Dispatcher.dispatch_message(%RegisterUser{email: "ada@example.com"}, DispatchOptions.new!(actor: admin))
{:ok, %MyApp.Accounts.User{id: 13, email: "ada@example.com"}}
iex> MyApp.Dispatcher.dispatch_message(%DeleteAccount{user_id: 7}, DispatchOptions.new!(actor: admin))
{:error, :mfa_required}
```

Registering worked, because `RegisterUser` does not ask for multi-factor authentication. Deleting stopped at
`MyApp.RequireMFA`. Verify the factor and try again:

```elixir
iex> MyApp.Dispatcher.dispatch_message(%DeleteAccount{user_id: 7}, DispatchOptions.new!(actor: %{admin | mfa_verified?: true}))
{:ok, %MyApp.Accounts.User{id: 7, email: nil}}
```

An actor without the scope never reaches the multi-factor check:

```elixir
iex> MyApp.Dispatcher.dispatch_message(%DeleteAccount{user_id: 7}, DispatchOptions.new!(actor: %{id: 2, scopes: []}))
{:error, :forbidden}
```

## What you built

- Messages that carry their own facts, and handlers that only do the work.
- Middleware that applies each policy once, for every message, by reading those facts.
- A dispatcher that is the single place where the order is decided.

To go further, [Write a middleware](../how-to/write-middleware.md) covers middleware in depth,
[Test with Mox](../how-to/test-with-mox.md) shows how callers test against the dispatcher,
[Handlers and the context](../explanations/handlers-and-context.md) explains why the pieces are shaped this way, and
[The compile-time model](../explanations/compile-time-model.md) covers what the build checks for you.
