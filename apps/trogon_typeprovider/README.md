# Trogon.TypeProvider

**A compile-time type mapping system that converts between string type names and Elixir struct modules with zero
runtime overhead.**

**`Trogon.TypeProvider` generates efficient pattern-matching functions at compile time to bidirectionally map string
identifiers to Elixir structs**. It provides a clean tuple-based API that returns `{:ok, result}` for successful mappings
and `{:error, error}` for failures, ensuring predictable error handling throughout your application.

**This solves the common need for type serialization and deserialization in event-driven architectures, message queues,
and data persistence layers**. Instead of maintaining manual mapping logic or runtime lookups, `Trogon.TypeProvider`
automatically generates optimized functions that handle the conversion between human-readable type names and your
application's struct modules.

**`Trogon.TypeProvider` is particularly useful for developers building event sourcing systems, CQRS applications, or
any system that needs to serialize domain events and commands**. It's ideal for teams working with Commanded,
EventStore, or custom event-driven architectures where type safety and performance are critical requirements.

## Usage

### Basic TypeProvider

```elixir
defmodule MyApp.TypeProvider do
  use Trogon.TypeProvider

  # Register individual types
  register_type "user_created", MyApp.UserCreated
  register_type "user_updated", MyApp.UserUpdated
  register_type "user_deleted", MyApp.UserDeleted
end
```

### TypeProvider with Prefix

```elixir
defmodule MyApp.AccountTypeProvider do
  use Trogon.TypeProvider, prefix: "accounts."

  register_type "created", MyApp.AccountCreated
  register_type "updated", MyApp.AccountUpdated
  # Results in types: "accounts.created", "accounts.updated"
end
```

### Importing from Other TypeProviders

```elixir
defmodule MyApp.GlobalTypeProvider do
  use Trogon.TypeProvider

  # Import all types from other providers
  import_type_provider MyApp.UserTypeProvider
  import_type_provider MyApp.AccountTypeProvider

  # Add additional types
  register_type "system_started", MyApp.Events.SystemStarted
end
```
