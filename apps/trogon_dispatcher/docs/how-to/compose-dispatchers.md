# Compose dispatchers

There is one construct in this library, so composing dispatchers is a decision about your own boundaries rather
than a hierarchy the library imposes.

## Register messages in a leaf dispatcher

```elixir
defmodule MyApp.Accounts.Dispatcher do
  use Trogon.Dispatcher

  middleware MyApp.Accounts.RequireTenant

  register_message MyApp.Accounts.RegisterUser, kind: :command
  register_message MyApp.Accounts.GetUser, kind: :query
  register_message MyApp.Accounts.ArchiveUser, kind: :command, to: MyApp.Accounts.ArchiveUserHandler
end
```

See `Trogon.Dispatcher.register_message/2` for what `:kind` and `:to` require.

## Import one dispatcher into another

```elixir
defmodule MyApp.Dispatcher do
  use Trogon.Dispatcher

  middleware MyApp.Authorize

  import_dispatcher MyApp.Accounts.Dispatcher
  import_dispatcher MyApp.Billing.Dispatcher
end
```

See `Trogon.Dispatcher.import_dispatcher/1` and the Composition section of `Trogon.Dispatcher` for how the
imported middleware and registrations combine.

## Diamonds

Reaching the same registration through two different import paths is fine and dedupes silently:

```elixir
defmodule MyApp.Left do
  use Trogon.Dispatcher
  import_dispatcher MyApp.Billing.Dispatcher
end

defmodule MyApp.Right do
  use Trogon.Dispatcher
  import_dispatcher MyApp.Billing.Dispatcher
end

defmodule MyApp.Root do
  use Trogon.Dispatcher
  import_dispatcher MyApp.Left
  import_dispatcher MyApp.Right
end
```

Two paths that disagree raise `Trogon.Dispatcher.DuplicateMessageError` at compile time, and importing a dispatcher
that transitively imports you raises `Trogon.Dispatcher.CircularImportError`.

## Introspect what a dispatcher resolved

```elixir
MyApp.Dispatcher.__trogon_dispatcher__(:registrations)
MyApp.Dispatcher.__trogon_dispatcher__(:middleware)
MyApp.Dispatcher.__trogon_dispatcher__(:imports)
```

See the Generated API section of `Trogon.Dispatcher` for what each key returns.
