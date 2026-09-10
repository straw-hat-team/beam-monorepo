# Protocols

Every module that calls `use Trogon.ObjectId` or `use Trogon.UnionObjectId` has protocol
implementations generated into it. The implementations live in your module, not in this
library, so they do not appear in this documentation as modules of their own.

## Emitted format

Each protocol emits one of two forms: the *full* form, `#{prefix}#{separator}#{id}`, or the
*bare* form, `id` with no prefix.

| Protocol | Emits | Controlled by |
| --- | --- | --- |
| `String.Chars` | Full | Nothing, always full |
| `Jason.Encoder` | Full or bare | `:json_format` |
| `JSON.Encoder` | Full or bare | `:json_format` |
| `c:Ecto.Type.dump/1` and `to_storage/1` | Full or bare | `:storage_format` |
| `Phoenix.Param` | Full | Nothing, always full |
| `Phoenix.HTML.Safe` | Full, HTML escaped | Nothing, always full |

Given a type declared with `json_format: :drop_prefix`:

```elixir
defmodule MyApp.UserId do
  use Trogon.ObjectId, object_type: "user", json_format: :drop_prefix
end

user_id = MyApp.UserId.new!("abc-123")

to_string(user_id)                 #=> "user_abc-123"
JSON.encode!(user_id)              #=> "\"abc-123\""
Jason.encode!(user_id)             #=> "\"abc-123\""
Phoenix.Param.to_param(user_id)    #=> "user_abc-123"
```

## Why `Phoenix.Param` ignores `:json_format`

`Phoenix.Param.to_param/1` output has to survive a roundtrip back into your application, and
both `parse/1` and `c:Ecto.Type.cast/1` accept only the full form. A param emitted in the bare
form would fail to parse on the way back in, so `Phoenix.Param` always emits the full form
regardless of how the type is configured for JSON.

This matters even if you never render an object id into a URL yourself. `Phoenix.Param` sets
`@fallback_to_any true`, and its `Any` implementation matches any struct carrying an `:id`
key, which every object id does. Without a generated implementation, `~p"/users/#{user_id}"`
would silently produce `/users/abc-123` rather than `/users/user_abc-123`, with no error
raised at the point the wrong value was produced.

## Optional dependencies

Three of the protocols come from optional packages. Each implementation is wrapped in a
`Code.ensure_loaded?/1` check that is evaluated when *your* module is compiled, not when this
library is compiled.

| Protocol | Requires |
| --- | --- |
| `Jason.Encoder` | `:jason` |
| `JSON.Encoder` | Elixir 1.18 or later |
| `Phoenix.Param` | `:phoenix` |
| `Phoenix.HTML.Safe` | `:phoenix_html` |

If you add one of these packages after your object id modules have already been compiled,
recompile them so the implementation is generated:

```console
$ mix deps.compile --force my_app
```

`Jason.Encoder` and `JSON.Encoder` read the same `:json_format` option and are generated
together, so a type encodes identically no matter which of the two a caller reaches for.

## Union types

A `Trogon.UnionObjectId` delegates every protocol to the member it wraps, so the member's own
`:json_format` decides the encoded form:

```elixir
defmodule MyApp.PrincipalId do
  use Trogon.UnionObjectId, types: [MyApp.UserId, MyApp.SystemId]
end

principal = MyApp.PrincipalId.new(MyApp.UserId.new!("abc-123"))

JSON.encode!(principal)           #=> "\"abc-123\""
Phoenix.Param.to_param(principal) #=> "user_abc-123"
```
