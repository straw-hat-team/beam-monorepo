# Compose dispatchers

There is one construct in this library. A dispatcher that registers commands and a dispatcher that imports other
dispatchers are the same kind of module, so composition is a decision you make about your own boundaries rather than
a hierarchy the library imposes.

## Register commands in a leaf dispatcher

```elixir
defmodule MyApp.Accounts.Dispatcher do
  use Trogon.Dispatcher

  middleware MyApp.Accounts.RequireTenant

  register_command MyApp.Accounts.RegisterUser, kind: :command
  register_command MyApp.Accounts.GetUser, kind: :query
  register_command MyApp.Accounts.ArchiveUser, kind: :command, to: MyApp.Accounts.ArchiveUserHandler
end
```

`:kind` is required. It is `:command` or `:query`, and it has no default. Events are out of scope: this library
dispatches to exactly one handler and returns its response.

Both kinds travel the same pipeline and both go out through `dispatch_command/2`, so `command` is this library's
transport noun: the thing you register, dispatch, and handle. `:kind` is where the read and write distinction
lives. That keeps command query separation rather than dissolving it, and arguably states it more loudly than two
entry points would, because `:kind` is a required field that every registration has to answer. What the library
does not do is give commands and queries separate dispatch functions, which is a transport decision and not a
semantic one.

`:to` names the handler module and defaults to the command module itself, so a command that handles itself needs no
extra module.

A leaf dispatcher is a first-class entry point. `MyApp.Accounts.Dispatcher.dispatch_command/2` works on its own and
runs only its own middleware. You do not have to route everything through a root.

## Import one dispatcher into another

```elixir
defmodule MyApp.Dispatcher do
  use Trogon.Dispatcher, telemetry_prefix: [:my_app, :dispatcher]

  middleware MyApp.Authorize

  import_dispatcher MyApp.Accounts.Dispatcher
  import_dispatcher MyApp.Billing.Dispatcher
end
```

`import_dispatcher` lifts every registration out of the imported dispatcher at compile time, the way
`import_type_provider` works in `Trogon.TypeProvider`.

Middleware attaches per registration, not per dispatcher. The importer's middleware wraps whatever the imported
dispatcher already had:

- `MyApp.Dispatcher` dispatching `RegisterUser` runs `Authorize`, then `RequireTenant`, then the handler.
- `MyApp.Dispatcher` dispatching a Billing command runs `Authorize` and then the Billing chain. `RequireTenant` never
  touches it.

Composition is additive. An importer can add middleware around what it imports; it can never remove or reorder
middleware it inherited.

## Recompilation

Importing creates a compile-time dependency on the imported dispatcher, so adding a command to
`MyApp.Accounts.Dispatcher` recompiles `MyApp.Dispatcher` automatically.

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

A middleware reached through more than one path runs once. Dedup is keyed on the module together with its `init/1`
result, so the same middleware listed twice with different options stays as two distinct steps.

Two paths that disagree raise `Trogon.Dispatcher.DuplicateCommandError` at compile time. They disagree when the same
command resolves to a different handler, a different kind, or a different effective middleware chain. The compiler
tells you which command and which two chains, rather than picking one silently.

Importing a dispatcher that transitively imports you raises `Trogon.Dispatcher.CircularImportError` with the full
path.

## Introspect what a dispatcher resolved

```elixir
MyApp.Dispatcher.__trogon_dispatcher__(:registrations)
MyApp.Dispatcher.__trogon_dispatcher__(:middleware)
MyApp.Dispatcher.__trogon_dispatcher__(:imports)
MyApp.Dispatcher.__trogon_dispatcher__(:telemetry_prefix)
```

`:registrations` returns the flattened list, each entry carrying `:command`, `:handler`, `:kind`, `:registered_by`
and the resolved `:middleware` chain. This is what `import_dispatcher` reads, and it is the fastest way to see what a
composed dispatcher actually routes.
