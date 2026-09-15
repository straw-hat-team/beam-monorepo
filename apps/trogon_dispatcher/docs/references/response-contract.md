# The response contract

Every handler returns one of exactly three shapes. A middleware never returns a response directly: it returns a
`Trogon.Dispatcher.Context` whose `:response` field holds one of these same three shapes.

| Response | Meaning |
| --- | --- |
| `:ok` | success with no value |
| `{:ok, struct}` | success with a value, which must be a struct |
| `{:error, term}` | failure, with any term as the reason |

```elixir
@type response :: :ok | {:ok, struct()} | {:error, term()}
```

## Where the response lives

A handler's `handle_message/2` returns a response. The stage that calls it puts that response onto the context,
and from there the context is what travels back out through the middleware. So a middleware reads
`context.response` and writes it with `Trogon.Dispatcher.Context.put_response/2`, and the dispatcher returns the
final context's response to the caller.

A middleware that halts, meaning it does not call `next`, must put a response itself. A context that reaches a stage
boundary with no response is a contract violation.

## The success value is a struct

`{:ok, value}` requires `is_struct(value)`. A bare map, a keyword list, a list, a binary, an integer or `nil` is a
contract violation, not a success.

The reason is that the success value crosses a boundary. A struct names its own shape, so a caller reading
`{:ok, %User{}}` knows what it received and a change to that shape is a change to a named type. A map is anonymous
and turns the boundary into an untyped payload.

A list is rejected for the same reason and one more: a collection result is a thing with a name. Return a struct that
holds the list.

```elixir
def handle_message(%ListUsers{}, _context) do
  {:ok, %UserList{entries: users, total: length(users)}}
end
```

## The error term is anything

`{:error, term}` accepts any term. The library does not require `Trogon.Error` or any other error type. Errors are
the host application's vocabulary.

## Commands do not have to return a value

A command whose outcome is only the effect returns `:ok`. There is no `{:ok, nil}` and no `{:ok, :ok}`.

## Violations raise

A response that is none of the three shapes raises `Trogon.Dispatcher.InvalidResponseError`, naming the module that
produced it, the message being dispatched, the dispatcher, and the offending value.

This is a raise rather than an `{:error, _}` because it is a bug in first-party code rather than a domain outcome.
`Plug` does the same when a plug fails to return a `Plug.Conn`. An application cannot meaningfully handle "my own
handler returned garbage" at the call site.

The check runs at every stage boundary: around each middleware's return and around the handler's return. Checking
once at the outermost boundary would be cheaper by a few pattern matches but could not say which module was at
fault, and attribution is the point of the error.

## Errors the library returns as values

Two conditions are outcomes rather than bugs, so they come back as terms:

| Condition | Result |
| --- | --- |
| dispatching a struct no dispatcher registered | `{:error, %Trogon.Dispatcher.UnregisteredMessageError{}}` |
| a handler or middleware returning `{:error, reason}` | `{:error, reason}`, untouched |

## Errors the library raises

| Condition | Exception | When |
| --- | --- | --- |
| a response that is not `:ok`, `{:ok, struct}` or `{:error, term}`, including a middleware that halted without putting one | `Trogon.Dispatcher.InvalidResponseError` | runtime |
| a middleware returning something other than a `Trogon.Dispatcher.Context` | `Trogon.Dispatcher.InvalidContextError` | runtime |
| a second argument that is not a `DispatchOptions` | `ArgumentError` | runtime |
| an exception raised inside a handler or middleware | the original exception, untouched | runtime |
| the same message reached with a different handler, kind, or middleware chain | `Trogon.Dispatcher.DuplicateMessageError` | compile time |
| a dispatcher importing itself, directly or transitively | `Trogon.Dispatcher.CircularImportError` | compile time |
| a registered handler that does not export `handle_message/2` | `ArgumentError` | compile time, via `@after_verify` |

An exception raised inside a handler or a middleware passes through untouched. The library does not wrap it, so the
original stacktrace survives. The `:exception` telemetry event fires first.

## The bang variants

`dispatch_message!/1` and `dispatch_message!/2` unwrap:

| Underlying response | `dispatch_message!` returns or raises |
| --- | --- |
| `:ok` | `:ok` |
| `{:ok, struct}` | the struct |
| `{:error, exception}` where the term is an exception struct | re-raises that exception as itself |
| `{:error, term}` otherwise | raises `Trogon.Dispatcher.DispatchError` carrying `:reason`, `:dispatched_message` and `:dispatcher` |

Re-raising an exception term as itself rather than wrapping it means a host whose errors are already exception
structs keeps its own error type at the top of the stacktrace, and a `rescue` clause matching that type still works.
