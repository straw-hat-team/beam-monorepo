# The compile-time model

Everything this library decides, it decides while your project compiles. At runtime a dispatch is a pattern match
followed by a chain of direct function calls. There is no registry process, no ETS table, no map lookup, and no
runtime configuration.

## What `use Trogon.Dispatcher` does

`use` registers four accumulating module attributes (middleware, registrations, imported dispatchers, import edges),
declares the four `dispatch_message` callbacks on the module so it is a behaviour, and installs `@before_compile` and
`@after_verify` hooks.

`middleware`, `register_message` and `import_dispatcher` are macros that accumulate into those attributes. They
validate as they go, so a bad `:kind`, a message module that defines no struct, a middleware that does not export
`call/3`, or an import of something that is not a dispatcher fails at the line that caused it.

## What `@before_compile` does

At `@before_compile` the accumulated state is resolved into one flat list of registrations. Each entry carries the
message, the handler, the kind, the dispatcher that registered it, and the fully resolved middleware chain for that
one message.

Local middleware is prefixed onto every registration, including the ones lifted in by `import_dispatcher`. That is
what makes composition additive: an importer wraps what it imported and cannot reorder or remove it.

The chain is then deduplicated on `{module, init_result}`, keeping the earliest position. Keying on the `init/1`
result rather than the module alone is what lets the same middleware appear twice with different options while a
middleware reached through two import paths still runs once. The one behavior this costs is that a deliberate,
identical double-listing of the same middleware collapses to one.

Finally, registrations reached more than once are collapsed when they are identical and raise
`Trogon.Dispatcher.DuplicateMessageError` when they are not.

## What gets generated

For each registration, one `dispatch_message/2` clause matching the message struct, plus one private function per
middleware stage and one for the handler:

```elixir
def dispatch_message(%RegisterUser{} = message, %DispatchOptions{} = options) do
  context = %Context{message: message, kind: :command, dispatcher: __MODULE__, registered_by: MyApp.Accounts.Dispatcher, ...}
  metadata = %{message: RegisterUser, kind: :command, dispatcher: __MODULE__, registered_by: MyApp.Accounts.Dispatcher, context: context}

  :telemetry.span([:my_app, :dispatcher, :dispatch], metadata, fn ->
    final = __trogon_dispatcher_stage_0_0__(context)
    {final.response, Trogon.Dispatcher.__stop_metadata__(metadata, final)}
  end)
end

defp __trogon_dispatcher_stage_0_0__(context) do
  Trogon.Dispatcher.__validate__(MyApp.Authorize.call(context, &__trogon_dispatcher_stage_0_1__/1, []), MyApp.Authorize, context)
end

defp __trogon_dispatcher_stage_0_1__(context) do
  Trogon.Dispatcher.__validate_response__(MyApp.Accounts.RegisterUser.handle_message(context.message, context), MyApp.Accounts.RegisterUser, context)
end
```

Every stage takes a context and returns a context, so the chain is a composition of one function type. The handler
is the one place the two types meet: it returns a response and the stage that calls it puts that response onto the
context. `__stop_metadata__/2` therefore sees the context the pipeline finished with, not the one it started from,
so anything a middleware assigned is on the `:stop` event.

Routing is therefore the BEAM's own multi-clause dispatch on the struct's `__struct__` key.

Two catch-all clauses close the function. A struct that was never registered returns
`{:error, %UnregisteredMessageError{}}`, because an unregistered message is a wiring state the caller can handle. A
second argument that is not a `DispatchOptions` raises `ArgumentError`, because that is a call-site bug and not a
domain outcome. `dispatch_message/2` is total: any term in the message position gets an answer rather than a
`FunctionClauseError`.

## Why `@after_verify` rather than `@after_compile`

A registered handler must export `handle_message/2`, but at `@before_compile` time the handler module may still be
compiling, so `function_exported?/3` cannot answer yet. `@after_compile` is not reliable either: under the parallel
compiler the handler still may not be verified.

`@after_verify` (Elixir 1.14 and later) runs after the module is verified, which is late enough for the check to be
correct. That is why this package requires Elixir 1.14 while its siblings require 1.13.

The tradeoff is that `@after_verify` runs inside the parallel checker's own process. The failure is reported as a
compile error and exits the build non-zero, but it does not propagate as an exception into whoever called
`Code.compile_string/1`. That matters only when writing tests against the check itself.

## Recompilation

`import_dispatcher` reads the imported dispatcher's `__trogon_dispatcher__/1`. That remote call inside a macro is a
real compile-time dependency, so the importer recompiles when the imported dispatcher changes. You never have to
remember to touch the root.

## What this buys and what it costs

It buys a dispatch that costs a pattern match, and errors that surface at compile time with the offending line rather
than at 3am in production.

It costs runtime flexibility. There is no way to register a message at runtime, no way to reconfigure middleware from
application config, and no way to swap a handler without recompiling. That is the intended trade: the set of messages
an application handles is part of its source code.
