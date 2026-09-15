# Why wrapping middleware

`Trogon.Dispatcher.Middleware` uses `call(context, next, options)` where `next` is a context-to-context function. A
middleware receives the rest of the pipeline as a function and decides whether, and with what, to call it. That is a
Rack style wrapping model rather than the `Plug.call(conn, opts)` reduce shape, even though this library otherwise
borrows heavily from Plug. The resemblance to Rack is in the wrapping, not in the signature: Rack's own callback is
`call(env)` and each middleware holds the next app in its own state. For the `next`-as-an-argument contract the
closer relatives are Koa's `(ctx, next)`, ASP.NET Core's `RequestDelegate next` and MassTransit's `Send(context,
next)`.

## One data type

A middleware deals with `Trogon.Dispatcher.Context` and nothing else. It takes a context, it returns a context. The
message is a field. The response is a field. Neither is ever an argument or a return value of its own.

That is a deliberate constraint rather than an accident of the implementation. A middleware whose input and output
types differ is two things wearing one name: a transformer on the way in and a different transformer on the way
out, with the author responsible for remembering which leg they are on. A middleware whose input and output are the
same type is one thing, and `next` is just another function of that type. It composes with itself, it composes with
the pipeline, and a test for it asserts on the same struct it was given.

It also gives a backward channel for free. Anything an inner stage writes to assigns or private is on the struct
that comes back out of `next`, so an outer middleware can read it without the library inventing a second slot to
carry annotations upward. The `:stop` telemetry event carries that same final context, which means a middleware
that wants to enrich the span does it by writing to the context it returns.

This is not a novel position. [Prior art](prior-art.md) walks through MediatR, Koa, Rack, Plug, Tesla, tower,
Django, Go and others with a snippet from each, and the short version is that two ecosystems ran this experiment and
moved the same direction: Rack to Plug, and Express to Koa.

## The reduce shape cannot wrap

`Plug` reduces: each plug takes a connection and returns a connection, and the pipeline halts by flagging the
connection. The types are right, but the shape is not. A reduce has no way to hold a frame open across the rest of
the pipeline, so a middleware that wants to time the handler, open a span around it, rescue it or retry it needs a
second callback, something like `call/2` on the way in and `after_call/3` on the way out. That splits one concern
across two functions, forces the middleware to stash state somewhere between them, and makes the ordering rules for
the second callback a thing users have to memorize.

With the wrapping shape, both directions are the same function body:

```elixir
def call(context, next, _options) do
  started_at = System.monotonic_time()

  context
  |> next.()
  |> Context.put_private(__MODULE__, System.monotonic_time() - started_at)
end
```

Halting needs no flag and no `halt/1` helper. Not calling `next` is the halt, and it is visible in the code rather
than encoded in a field. What a halting middleware owes the pipeline is a response:

```elixir
Context.put_response(context, {:error, :unauthorized})
```

## Why options are a third argument rather than a closure

`init/1` runs at compile time and its result is baked into the generated pipeline as a literal. Passing that result
as a third argument keeps the middleware a plain module with no state, and keeps the generated code a direct call:

```elixir
defp stage_3_1(context) do
  MyApp.RequireTenant.call(context, &stage_3_2/1, "acme")
end
```

An earlier iteration of the design had `call(context, next)` with options captured in the closure. That reads more
cleanly in isolation but leaves nowhere for the `init/1` result to go once options are compile-time values, and it
makes a middleware harder to call directly in a test.

## The cost

The wrapping shape builds a call stack as deep as the middleware chain. For an in-process synchronous dispatch that
is a handful of frames and no allocation beyond the captures, all of which are compile-time literals here. The chain
is not built at runtime: `import_dispatcher` flattens at compile time, the chain per message is known, and each stage
is a private function with a statically known successor.

The real cost is that a middleware that forgets to call `next` silently swallows the dispatch. That failure mode is
loud in practice, because every stage boundary checks both halves of the contract: a stage that returns something
other than a context raises `Trogon.Dispatcher.InvalidContextError`, and a context carrying no valid response raises
`Trogon.Dispatcher.InvalidResponseError`. Both name the exact module at fault.
