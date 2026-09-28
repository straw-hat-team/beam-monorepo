# Handlers and the context

A handler is `handle_message(message, context)`, and the context also carries the message. That looks like
duplication. It is deliberate, and it is one of a small set of decisions about where each piece of a dispatch lives.

## Why the handler takes the message and the context

The message argument is there for the function head. Handlers are written as pattern matches on the message:

```elixir
def handle_message(%DeleteAccount{user_id: user_id}, context) do
```

That head is what makes a handler readable, and on Elixir 1.20 it is also what the type checker reads. The
dispatcher calls the handler from the generated clause that already matched the message, with the handler module
written out, so a registration whose handler cannot accept the message is a compile warning at the `register_message`
line. See [The compile-time model](compile-time-model.md).

A handler that took only the context would lose both. The head would become `%Context{message: %DeleteAccount{} =
message}`, and because `Context.message` is typed as any struct, the checker could no longer tell a wrong handler from
a right one.

The context argument is there for everything that is about the dispatch rather than the message: the actor, the
correlation and causation ids, and whatever middleware assigned.

Elixir has this shape elsewhere. A Phoenix action is `action(conn, params)` even though `conn.params` holds the same
params, because matching on params in the head is the common case. An Absinthe resolver receives its arguments
separately from the resolution that also contains them.

Nothing is copied. Both arguments point at the same immutable term.

## Why the context carries the message anyway

Middleware needs it. Authorization reads the permission the message asks for, logging and tracing name it, and
`Trogon.Dispatcher.Test.call_middleware/3` hands a middleware a context and a `next`, never a separate message. Keeping the message on the
context is what lets a middleware stay a function from context to context.

## The handler receives the message that was dispatched

The handler is called with the message the dispatch clause matched, not with whatever `context.message` holds when
the chain reaches it. Middleware may add assigns, private data and a response, but it does not replace the message.
There is no function for it on `Trogon.Dispatcher.Context`, and a middleware that rebuilds the struct with a different
message changes what later middleware sees without changing what the handler receives.

That is the price of the compile-time type check, and it matches the contract: the message is what the caller asked
for, and a middleware that wants a different request should dispatch a different message.

## Where per-message policy lives

Some messages need something others do not: a stricter permission, a second factor, a shorter timeout. That fact
could live on the message, on the handler, or on the registration.

**On the message, read by dispatcher-wide middleware.** This is the design.

```elixir
defmodule MyApp.Accounts.DeleteAccount do
  defstruct [:user_id]

  def auth_scope, do: "accounts:delete"
  def requires_mfa?, do: true
end
```

The message states the fact next to its fields, where a reader of that file sees it. The dispatcher declares which
middleware runs and in what order, once. The two concerns stay separate: what a message needs is its own business,
and how the application enforces it is the dispatcher's. ASP.NET Core's `[Authorize]` attribute works the same way:
the attribute is only metadata on the endpoint, and one authorization middleware reads it.

The library gives these facts no names of its own. [Write a middleware](../how-to/write-middleware.md) explains why
under "Per-message metadata".

**On the handler, as a decorator.** A library such as `decorator` wraps the handler's function body. That wrapper
sits inside the dispatch rather than around it, sees raw arguments rather than the context, and cannot put a response
or stop the dispatch the way middleware does. It gets none of the compile-time checks middleware gets, and it is
invisible to the dispatcher's introspection and telemetry. It would be a second middleware system with different
rules.

**On the registration, as a per-message middleware list.** This keeps the wiring in the dispatcher, but it spreads
the order that runs for a message across two places: the dispatcher's `middleware` block and the registration. The
same effect is already available, because middleware attaches per registration and a small dispatcher is a scope:

```elixir
defmodule MyApp.Accounts.Sensitive do
  use Trogon.Dispatcher

  middleware MyApp.RequireMFA

  register_message DeleteAccount, kind: :command, to: DeleteAccountHandler
end
```

Import it into the application dispatcher, and only `DeleteAccount` runs `MyApp.RequireMFA`. A registration option
may be worth adding if that pattern becomes common enough to feel heavy, but it would be a second way to say
something composition already says.

## Summary

| Concern | Lives on | Why |
| --- | --- | --- |
| The work | The handler | It is the only code that knows how |
| Facts a message needs | The message module | A reader of the message sees them |
| Which policies run, in what order | The dispatcher's `middleware` | One place decides the order |
| Data for one dispatch | The context's assigns and private | It exists only for that dispatch |
