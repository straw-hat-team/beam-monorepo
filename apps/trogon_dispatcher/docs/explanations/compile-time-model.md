# The compile-time model

Everything this library decides, it decides while your project compiles. At runtime a dispatch is a pattern match
followed by a chain of direct function calls. There is no registry process, no ETS table, no map lookup, and no
runtime configuration.

## Mistakes fail the build

`middleware`, `register_message` and `import_dispatcher` validate as they go. A bad `:kind`, a message module that
defines no struct, a middleware that does not export `call/3`, an `init/1` that does not return a struct, or an import
of something that is not a dispatcher fails at the line that caused it.

A registered handler that does not export `handle_message/2` also fails the build. That check has to wait until the
handler module is verified, so it runs in an `@after_verify` callback.

On Elixir 1.20, a handler whose `handle_message/2` heads cannot match the registered message is a type warning at the
`register_message` line, and again at each `import_dispatcher` line that brings the registration in, so `to:`
pointing at the wrong handler fails a `--warnings-as-errors` build. The check needs the handler to pattern-match the
message struct in its function head; a catch-all head accepts anything.

## How the middleware chain is resolved

A dispatcher's own middleware wraps every message it handles, including the ones it gets through
`import_dispatcher`. Composition is additive: an importer wraps what it imported and cannot reorder or remove it.

The chain is exactly what was declared. A middleware that appears more than once, whether listed twice on one
dispatcher or declared by both an importer and the dispatcher it imports, runs each time it appears. Nothing is
collapsed, so a retry or a timer can sit at more than one layer on purpose. A middleware that must run only once per
dispatch guards itself; see [Write a middleware](../how-to/write-middleware.md).

The same registration reached more than once through imports is fine, and dedupes. Registrations that disagree
raise `Trogon.Dispatcher.DuplicateMessageError`, and so do two dispatchers that each register the same message: a
message has one owning boundary, and `registered_by` reports it.

## What happens when you dispatch

Each registered message gets its own `dispatch_message/2` clause, so routing is the BEAM's own multi-clause dispatch
on the struct.

- A registered struct runs through its middleware chain and handler inside a `:telemetry.span/3`. The `:stop` event
  carries the context the pipeline finished with, so anything a middleware assigned is on it.
- A struct that was never registered returns `{:error, %Trogon.Dispatcher.UnregisteredMessageError{}}`, because an
  unregistered message is a wiring state the caller can handle.
- A message that is not a struct, or options that are not a `Trogon.Dispatcher.DispatchOptions`, raise
  `ArgumentError`. Both are call-site bugs, not domain outcomes, so returning an error value for them would dress a
  type error up as a routing result.

## Types are checked before runtime, not during it

The dispatch path does not re-check the shape of what it is handed. `Trogon.Dispatcher.DispatchOptions` rejects an
unknown or repeated key when it is built, and nothing more: whether `assigns` is a map with atom keys is stated by its type, and
caught before runtime by the Elixir type checker where it can see the value, and by `Trogon.Credo.Plugin.Dispatcher`
for literals and direct context updates the type checker cannot follow across modules. A value that slips past both is
a bug at the call site, and checking for it on every dispatch would charge every caller for it.

## Middleware options are fixed at compile time

`init/1` runs once, while the dispatcher compiles, and its result is baked into the code. Anything it reads, such as
application config or environment variables, is captured at build time, so a release will not see runtime config
there. Read runtime values inside `call/3` instead.

## Recompilation

A dispatcher that imports another recompiles whenever the imported one changes. You never have to remember to touch
the root.

## What this buys and what it costs

It buys a dispatch that costs a pattern match, and errors that surface at compile time with the offending line rather
than at 3am in production.

It costs runtime flexibility. There is no way to register a message at runtime, no way to reconfigure middleware from
application config, and no way to swap a handler without recompiling. That is the intended trade: the set of messages
an application handles is part of its source code.
