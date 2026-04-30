# Trogon.ObjectId

**Type-safe, prefixed object IDs for Elixir applications.** Each ID type is its own struct, so `UserId` and `OrderId` can never be confused at compile time or runtime.

**Define an ID with `use Trogon.ObjectId`, and you get creation, parsing, string conversion, JSON encoding, and Ecto type callbacks out of the box.** IDs are stored as `{prefix}{separator}{value}` strings (e.g., `"user_abc-123"`), with configurable storage and JSON formats. Union types (`Trogon.UnionObjectId`) let a single field accept any of several ID types, discriminated by prefix. Proto-driven definitions derive prefixes and separators from protobuf enum annotations.

**Raw string IDs lose their meaning the moment they leave the function that created them — a user ID passed where an order ID was expected is a silent, runtime bug.** Trogon.ObjectId eliminates that class of error by making every ID a distinct struct that pattern-matches and type-specs enforce automatically.

**Built for teams writing domain-driven Elixir services that use Ecto for persistence and need human-readable, type-safe identifiers across commands, events, and read models.**

## How-to

### Define an ObjectId

```elixir
defmodule MyApp.UserId do
  use Trogon.ObjectId, object_type: "user"
end

{:ok, id} = MyApp.UserId.new("abc-123")
"user_abc-123" = to_string(id)
{:ok, ^id} = MyApp.UserId.parse("user_abc-123")
```

See `Trogon.ObjectId` module docs for all options (`separator`, `storage_format`, `json_format`, `validate`, `proto`).

### Define a union of ObjectId types

```elixir
defmodule MyApp.PrincipalId do
  use Trogon.UnionObjectId, types: [MyApp.TenantId, MyApp.SystemId]
end

{:ok, principal} = MyApp.PrincipalId.parse("tenant_abc-123")
#=> {:ok, %MyApp.PrincipalId{id: %MyApp.TenantId{id: "abc-123"}}}
```
