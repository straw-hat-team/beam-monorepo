defmodule Trogon.Dispatcher do
  @moduledoc """
  An in-process, stateless, synchronous message and query dispatcher.

  A host app declares which message structs exist, composes middleware around them, and calls `dispatch_message/2`.
  The library owns cross-cutting concerns (telemetry emission, middleware composition, test tooling) and owns no
  architecture: there are no events, no aggregates, no repos, and no processes.

  ## Example

      defmodule MyApp.Accounts.Dispatcher do
        use Trogon.Dispatcher

        middleware MyApp.Accounts.RequireTenant

        register_message MyApp.Accounts.RegisterUser,  kind: :command
        register_message MyApp.Accounts.GetUser, kind: :query
        register_message MyApp.Accounts.ArchiveUser, kind: :command, to: MyApp.Accounts.ArchiveUserHandler
      end

      defmodule MyApp.Dispatcher do
        use Trogon.Dispatcher

        middleware MyApp.Authorize

        import_dispatcher MyApp.Accounts.Dispatcher
        import_dispatcher MyApp.Billing.Dispatcher
      end

  There is one construct. A dispatcher that imports others is the same kind of thing as one that registers commands
  directly, and a leaf dispatcher is a first-class entry point. The library does not decide at what level a boundary
  is self-sufficient; you do.

  ## Composition

  `import_dispatcher` flattens at compile time. The importer's middleware wraps the imported dispatcher's, per
  registration, so `MyApp.Dispatcher` dispatching `RegisterUser` runs `Authorize -> RequireTenant -> handler` while a
  Billing message is untouched by `RequireTenant`. Composition is additive: nothing can remove or reorder middleware
  it inherited. A middleware that appears more than once in a chain, locally or through imports, runs each time it
  appears.

  Reaching the same registration twice through a diamond of imports dedupes silently. Two paths that disagree on the
  handler, the kind, the effective middleware chain, or the dispatcher that registered the message raise
  `Trogon.Dispatcher.DuplicateMessageError` at compile time.

  ## Generated API

  Each dispatcher gets `dispatch_message/1`, `dispatch_message/2`, `dispatch_message!/1` and `dispatch_message!/2`,
  declared as callbacks on the dispatcher module itself. That makes every dispatcher a behaviour, so a host injects
  the module and mocks it with `Mox.defmock(MyApp.DispatcherMock, for: MyApp.Dispatcher)` without a separate
  behaviour module.

  `dispatch_message/2` returns the final context's `:response`, per the contract in `Trogon.Dispatcher.Handler`. It
  raises `ArgumentError` when the first argument is not a struct, or the second is not a
  `Trogon.Dispatcher.DispatchOptions.t()`. The bang variants unwrap that response:

  | `:response` | `dispatch_message!` returns or raises |
  | --- | --- |
  | `:ok` | `:ok` |
  | `{:ok, struct}` | the struct |
  | `{:error, exception}` where the term is an exception struct | re-raises that exception as itself |
  | `{:error, term}` otherwise | raises `Trogon.Dispatcher.DispatchError` carrying `:reason`, `:dispatched_message` and `:dispatcher` |

  Re-raising an exception term as itself, rather than wrapping it, means a host whose errors are already exception
  structs keeps its own error type at the top of the stacktrace, and a `rescue` clause matching that type still
  works.

  It also gets `__trogon_dispatcher__/1` for introspection, which is what `import_dispatcher` reads.
  `:registrations` returns the flattened list, each entry a map with `:message`, `:handler`, `:kind`,
  `:registered_by` and the resolved `:middleware` chain; `:middleware` and `:imports` return what was declared
  locally on this dispatcher.

  ## Telemetry

  Every registered dispatch is a `:telemetry.span/3` under `[:trogon_dispatcher, :dispatch, *]`. The event names
  are the same for every dispatcher; tell them apart with the `:dispatcher` and `:registered_by` metadata rather
  than the event name. A message reached through a root dispatcher emits once, not once per layer, and dispatching
  an unregistered message emits nothing (see `Trogon.Dispatcher.UnregisteredMessageError`).

  | Event | Measurements |
  | --- | --- |
  | `[:trogon_dispatcher, :dispatch, :start]` | `:system_time`, `:monotonic_time` |
  | `[:trogon_dispatcher, :dispatch, :stop]` | `:duration`, `:monotonic_time` |
  | `[:trogon_dispatcher, :dispatch, :exception]` | `:duration`, `:monotonic_time` |

  Start metadata:

    * `:message` - the message module
    * `:kind` - `:command` or `:query`
    * `:dispatcher` - the module whose `dispatch_message/2` was called
    * `:registered_by` - the dispatcher that declared the registration
    * `:handler` - the module whose `handle_message/2` runs
    * `:context` - the `Trogon.Dispatcher.Context` the pipeline began with
    * `:telemetry_span_context` - added by `:telemetry.span/3`

  Stop metadata carries all of the above, with `:context` updated to the context the pipeline finished with, plus
  `:result` (`:ok` or `:error`) and, only when `:result` is `:error`, `:error` with the error term.

  Exception metadata carries the same keys as start metadata, plus `:reason` and `:stacktrace`; `:kind` is
  overwritten by `:telemetry.span/3` with `:error`, `:throw` or `:exit`. An exception raised inside a handler or a
  middleware passes through untouched after this event fires; the library does not wrap it.
  """

  alias Trogon.Dispatcher.CircularImportError
  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchError
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.DuplicateMessageError
  alias Trogon.Dispatcher.InvalidContextError
  alias Trogon.Dispatcher.InvalidResponseError
  alias Trogon.Dispatcher.Middleware
  alias Trogon.Dispatcher.UnregisteredMessageError

  @type kind :: :command | :query
  @type response :: :ok | {:ok, struct()} | {:error, term()}
  @type registration :: %{
          message: module(),
          handler: module(),
          kind: kind(),
          registered_by: module(),
          middleware: [{module(), term()}]
        }

  @telemetry_event [:trogon_dispatcher, :dispatch]

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import Trogon.Dispatcher,
        only: [middleware: 1, middleware: 2, register_message: 2, import_dispatcher: 1]

      Trogon.Dispatcher.__validate_options__(opts)

      Module.register_attribute(__MODULE__, :trogon_dispatcher_middleware, accumulate: true)
      Module.register_attribute(__MODULE__, :trogon_dispatcher_registrations, accumulate: true)
      Module.register_attribute(__MODULE__, :trogon_dispatcher_imported, accumulate: true)
      Module.register_attribute(__MODULE__, :trogon_dispatcher_imports, accumulate: true)
      Module.register_attribute(__MODULE__, :trogon_dispatcher_import_lines, accumulate: true)

      @callback dispatch_message(message :: struct()) :: Trogon.Dispatcher.response()
      @callback dispatch_message(message :: struct(), options :: Trogon.Dispatcher.DispatchOptions.t()) ::
                  Trogon.Dispatcher.response()
      @callback dispatch_message!(message :: struct()) :: :ok | struct()
      @callback dispatch_message!(message :: struct(), options :: Trogon.Dispatcher.DispatchOptions.t()) ::
                  :ok | struct()

      @before_compile Trogon.Dispatcher
      @after_verify Trogon.Dispatcher
    end
  end

  @doc """
  Adds a middleware to every message this dispatcher resolves.

  Options run through the middleware's `init/1` at compile time and the result is baked into the generated pipeline
  as a literal, so it must be a term that can be represented in AST.

  ## Example

      middleware MyApp.Authorize
      middleware MyApp.RateLimit, max_per_minute: 60
  """
  @spec middleware(module()) :: Macro.t()
  defmacro middleware(middleware_mod) do
    quote bind_quoted: [middleware_mod: middleware_mod] do
      Trogon.Dispatcher.__middleware__(__MODULE__, middleware_mod, [])
    end
  end

  @spec middleware(module(), term()) :: Macro.t()
  defmacro middleware(middleware_mod, opts) do
    quote bind_quoted: [middleware_mod: middleware_mod, opts: opts] do
      Trogon.Dispatcher.__middleware__(__MODULE__, middleware_mod, opts)
    end
  end

  @doc """
  Registers a message struct with this dispatcher.

  `:kind` is required, has no default, and must be `:command` or `:query`. Both kinds travel the same pipeline and
  both go out through `dispatch_message/2`: `message` is the genus and `:command` and `:query` are the two species,
  so `:kind` is what carries the read and write distinction. Events are out of scope. `:to` names the handler and
  defaults to the message module itself.

  ## Example

      register_message MyApp.Accounts.RegisterUser, kind: :command
      register_message MyApp.Accounts.GetUser, kind: :query
      register_message MyApp.Accounts.ArchiveUser, kind: :command, to: MyApp.Accounts.ArchiveUserHandler
  """
  @spec register_message(module(), keyword()) :: Macro.t()
  defmacro register_message(message_mod, opts) do
    quote bind_quoted: [message_mod: message_mod, opts: opts] do
      Trogon.Dispatcher.__register_message__(__MODULE__, message_mod, opts, __ENV__.line)
    end
  end

  @doc """
  Lifts every registration out of another dispatcher, flattened at compile time.

  Mirrors `import_type_provider` from `Trogon.TypeProvider`. The imported dispatcher's middleware stays attached to
  its own registrations; this dispatcher's middleware wraps around it.

  ## Example

      import_dispatcher MyApp.Accounts.Dispatcher
  """
  @spec import_dispatcher(module()) :: Macro.t()
  defmacro import_dispatcher(dispatcher_mod) do
    quote bind_quoted: [dispatcher_mod: dispatcher_mod] do
      Trogon.Dispatcher.__import_dispatcher__(__MODULE__, dispatcher_mod, __ENV__.line)
    end
  end

  defmacro __before_compile__(env) do
    module = env.module
    options_mod = DispatchOptions
    unregistered_mod = UnregisteredMessageError

    local_middleware = accumulated(module, :trogon_dispatcher_middleware)
    imports = accumulated(module, :trogon_dispatcher_imports)
    local_registrations = local_registrations(module)
    imported_registrations = accumulated(module, :trogon_dispatcher_imported)

    registrations =
      resolve_registrations(module, local_middleware, local_registrations ++ imported_registrations)

    lines = registration_lines(module)

    clauses =
      Enum.map(registrations, fn registration ->
        dispatch_clause(registration, options_mod, Map.get(lines, registration.message, env.line))
      end)

    quote do
      unquote(introspection(registrations, local_middleware, imports))
      unquote(entrypoints(options_mod))
      unquote(clauses)
      unquote(fallbacks(options_mod, unregistered_mod))
    end
  end

  defp introspection(registrations, local_middleware, imports) do
    quote do
      @doc false
      def __trogon_dispatcher__(:registrations), do: unquote(Macro.escape(registrations))
      def __trogon_dispatcher__(:middleware), do: unquote(Macro.escape(local_middleware))
      def __trogon_dispatcher__(:imports), do: unquote(Macro.escape(imports))
    end
  end

  defp entrypoints(options_mod) do
    quote do
      def dispatch_message(message, options \\ %unquote(options_mod){})
      def dispatch_message!(message, options \\ %unquote(options_mod){})

      def dispatch_message!(message, options) do
        message
        |> dispatch_message(options)
        |> Trogon.Dispatcher.unwrap(message, __MODULE__)
      end
    end
  end

  defp fallbacks(options_mod, unregistered_mod) do
    quote do
      def dispatch_message(message, %unquote(options_mod){}) when is_struct(message) do
        {:error, unquote(unregistered_mod).exception(dispatched_message: message, dispatcher: __MODULE__)}
      end

      def dispatch_message(message, %unquote(options_mod){}) do
        raise ArgumentError,
              "expected a struct as the first argument, got: #{inspect(message)}"
      end

      def dispatch_message(_message, options) do
        raise ArgumentError,
              "expected a %#{inspect(unquote(options_mod))}{} as the second argument, got: #{inspect(options)}"
      end
    end
  end

  defp accumulated(module, attribute) do
    module |> Module.get_attribute(attribute) |> Enum.reverse()
  end

  defp local_registrations(module) do
    for {message_mod, handler_mod, kind, _line} <- accumulated(module, :trogon_dispatcher_registrations) do
      %{message: message_mod, handler: handler_mod, kind: kind, registered_by: module, middleware: []}
    end
  end

  defp registration_lines(module) do
    local_lines =
      for {message_mod, _handler_mod, _kind, line} <- accumulated(module, :trogon_dispatcher_registrations),
          do: {message_mod, line}

    Map.new(accumulated(module, :trogon_dispatcher_import_lines) ++ local_lines)
  end

  @doc false
  def unwrap(:ok, _message, _dispatcher), do: :ok
  def unwrap({:ok, value}, _message, _dispatcher), do: value
  def unwrap({:error, reason}, message, dispatcher), do: raise_error(reason, message, dispatcher)

  @doc false
  def __after_verify__(module) do
    for registration <- module.__trogon_dispatcher__(:registrations) do
      verify_handler(module, registration)
    end

    :ok
  end

  @doc false
  def __validate_options__([]), do: :ok

  def __validate_options__(opts) do
    raise ArgumentError, "use Trogon.Dispatcher takes no options, got: #{inspect(opts)}"
  end

  @doc false
  def __middleware__(module, middleware_mod, opts) do
    ensure_compiled!(middleware_mod)

    if not function_exported?(middleware_mod, :call, 3) do
      raise ArgumentError, """
      Invalid middleware #{inspect(middleware_mod)} in #{inspect(module)}

      Expected: #{inspect(middleware_mod)} to export call/3
      Problem: Module does not implement the Trogon.Dispatcher.Middleware behaviour

      To fix this, implement the behaviour:

          defmodule #{inspect(middleware_mod)} do
            @behaviour Trogon.Dispatcher.Middleware

            @impl true
            def call(context, next, _options) do
              next.(context)
            end
          end
      """
    end

    initialized = initialize_middleware!(middleware_mod, opts, " in #{inspect(module)}")

    Module.put_attribute(module, :trogon_dispatcher_middleware, {middleware_mod, initialized})
  end

  @doc false
  @spec initialize_middleware!(module(), Middleware.options(), String.t()) ::
          Middleware.init_result() | Middleware.options()
  def initialize_middleware!(middleware_mod, opts, location \\ "") do
    if function_exported?(middleware_mod, :init, 1) do
      case middleware_mod.init(opts) do
        initialized when is_struct(initialized) ->
          initialized

        other ->
          raise ArgumentError, """
          Invalid middleware #{inspect(middleware_mod)}#{location}

          Expected: #{inspect(middleware_mod)}.init/1 to return a struct
          Got: #{inspect(other)}

          To fix this, return a struct from init/1:

              defmodule #{inspect(middleware_mod)} do
                @behaviour Trogon.Dispatcher.Middleware

                defstruct [:max_per_minute]

                @impl true
                def init(opts), do: %__MODULE__{max_per_minute: Keyword.fetch!(opts, :max_per_minute)}

                @impl true
                def call(context, next, %__MODULE__{} = options) do
                  next.(context)
                end
              end
          """
      end
    else
      opts
    end
  end

  @doc false
  def __register_message__(module, message_mod, opts, line) do
    ensure_compiled!(message_mod)

    kind = Keyword.get(opts, :kind)

    if kind not in [:command, :query] do
      raise ArgumentError, """
      Invalid registration of #{inspect(message_mod)} in #{inspect(module)}

      Expected: kind: :command or kind: :query
      Got: #{inspect(kind)}

      :kind is required and has no default. It carries the read or write distinction; events are out of scope.

          register_message #{inspect(message_mod)}, kind: :command
      """
    end

    if not struct_module?(message_mod) do
      raise ArgumentError, """
      Invalid registration of #{inspect(message_mod)} in #{inspect(module)}

      Expected: #{inspect(message_mod)} to define a struct
      Problem: Module does not define a struct

      Messages are structs; routing is a pattern match on the struct head.

          defmodule #{inspect(message_mod)} do
            defstruct [:field]
          end
      """
    end

    handler_mod = Keyword.get(opts, :to, message_mod)

    Module.put_attribute(module, :trogon_dispatcher_registrations, {message_mod, handler_mod, kind, line})
  end

  @doc false
  def __import_dispatcher__(module, dispatcher_mod, line) do
    if module == dispatcher_mod do
      raise CircularImportError.exception(
              dispatcher: module,
              imported: dispatcher_mod,
              path: [module, dispatcher_mod]
            )
    end

    ensure_compiled!(dispatcher_mod)

    if not dispatcher?(dispatcher_mod) do
      raise ArgumentError, """
      Invalid dispatcher import in #{inspect(module)}

      Expected: #{inspect(dispatcher_mod)} to be a Trogon.Dispatcher
      Problem: Module does not use Trogon.Dispatcher

      To fix this, make sure the module you are importing uses the dispatcher:

          defmodule #{inspect(dispatcher_mod)} do
            use Trogon.Dispatcher

            register_message SomeCommand, kind: :command
          end
      """
    end

    check_cycle!(module, dispatcher_mod)

    Module.put_attribute(module, :trogon_dispatcher_imports, dispatcher_mod)

    for registration <- dispatcher_mod.__trogon_dispatcher__(:registrations) do
      Module.put_attribute(module, :trogon_dispatcher_imported, registration)
      Module.put_attribute(module, :trogon_dispatcher_import_lines, {registration.message, line})
    end

    :ok
  end

  defp resolve_registrations(module, local_middleware, registrations) do
    registrations
    |> Enum.map(&%{&1 | middleware: local_middleware ++ &1.middleware})
    |> Enum.reduce([], fn registration, acc ->
      case Enum.find(acc, &(&1.message == registration.message)) do
        nil ->
          acc ++ [registration]

        ^registration ->
          acc

        existing ->
          raise DuplicateMessageError.exception(
                  dispatched_message: registration.message,
                  dispatcher: module,
                  existing: existing,
                  conflicting: registration
                )
      end
    end)
  end

  defp dispatch_clause(registration, options_mod, line) do
    quote line: line do
      def dispatch_message(%unquote(registration.message){} = message, %unquote(options_mod){} = options) do
        Trogon.Dispatcher.dispatch(
          message,
          options,
          unquote(registration.kind),
          __MODULE__,
          unquote(registration.registered_by),
          unquote(Macro.escape(registration.middleware)),
          {unquote(registration.handler), &unquote(registration.handler).handle_message(message, &1)}
        )
      end
    end
  end

  @doc false
  def dispatch(message, options, kind, dispatcher, registered_by, middleware, {handler_mod, _handle} = handler) do
    context = Context.new(message, options, kind: kind, dispatcher: dispatcher, registered_by: registered_by)

    metadata = %{
      message: message.__struct__,
      kind: context.kind,
      dispatcher: context.dispatcher,
      registered_by: context.registered_by,
      handler: handler_mod,
      context: context
    }

    :telemetry.span(@telemetry_event, metadata, fn ->
      final = run(context, middleware, handler)
      {final.response, stop_metadata(metadata, final)}
    end)
  end

  defp run(context, [{middleware_mod, options} | rest], handler) do
    validate(middleware_mod.call(context, &run(&1, rest, handler), options), middleware_mod, context)
  end

  defp run(context, [], {handler_mod, handle}) do
    validate_response(handle.(context), handler_mod, context)
  end

  @doc false
  def validate(%Context{} = returned, module, _context) do
    validate_response(returned.response, module, returned)
  end

  def validate(returned, module, context) do
    raise InvalidContextError.exception(
            module: module,
            dispatched_message: context.message,
            dispatcher: context.dispatcher,
            returned: returned
          )
  end

  @doc false
  def validate_response(:ok, _module, context), do: %{context | response: :ok}

  def validate_response({:ok, value} = response, _module, context) when is_struct(value) do
    %{context | response: response}
  end

  def validate_response({:error, _reason} = response, _module, context) do
    %{context | response: response}
  end

  def validate_response(response, module, context) do
    raise InvalidResponseError.exception(
            module: module,
            dispatched_message: context.message,
            dispatcher: context.dispatcher,
            response: response
          )
  end

  @doc false
  def stop_metadata(metadata, %Context{} = context) do
    metadata |> Map.put(:context, context) |> result_metadata(context.response)
  end

  defp result_metadata(metadata, :ok), do: Map.put(metadata, :result, :ok)
  defp result_metadata(metadata, {:ok, _value}), do: Map.put(metadata, :result, :ok)

  defp result_metadata(metadata, {:error, reason}) do
    metadata |> Map.put(:result, :error) |> Map.put(:error, reason)
  end

  @doc false
  def raise_error(reason, _message, _dispatcher) when is_exception(reason) do
    raise reason
  end

  def raise_error(reason, message, dispatcher) do
    raise DispatchError.exception(reason: reason, dispatched_message: message, dispatcher: dispatcher)
  end

  defp verify_handler(module, registration) do
    loaded? = Code.ensure_loaded?(registration.handler)

    if not (loaded? and function_exported?(registration.handler, :handle_message, 2)) do
      raise ArgumentError, """
      Missing handler for #{inspect(registration.message)} in #{inspect(module)}

      Expected: #{inspect(registration.handler)} to export handle_message/2
      Problem: #{missing_reason(loaded?)}

      To fix this, implement the handler:

          defmodule #{inspect(registration.handler)} do
            @behaviour Trogon.Dispatcher.Handler

            @impl true
            def handle_message(message, context) do
              :ok
            end
          end

      Or point the registration somewhere else:

          register_message #{inspect(registration.message)}, kind: #{inspect(registration.kind)}, to: SomeHandler
      """
    end
  end

  defp missing_reason(true), do: "Module is loaded but does not export handle_message/2"
  defp missing_reason(false), do: "Module could not be loaded"

  defp check_cycle!(module, dispatcher_mod) do
    path = import_path(dispatcher_mod, module, [dispatcher_mod], [])

    if path do
      raise CircularImportError.exception(
              dispatcher: module,
              imported: dispatcher_mod,
              path: [module | path]
            )
    end
  end

  defp import_path(current, target, acc, seen) do
    cond do
      current == target ->
        Enum.reverse(acc)

      current in seen ->
        nil

      not dispatcher?(current) ->
        nil

      true ->
        seen = [current | seen]

        Enum.find_value(current.__trogon_dispatcher__(:imports), fn imported ->
          import_path(imported, target, [imported | acc], seen)
        end)
    end
  end

  defp dispatcher?(module) do
    function_exported?(module, :__trogon_dispatcher__, 1)
  end

  defp struct_module?(module) do
    function_exported?(module, :__struct__, 0)
  end

  defp ensure_compiled!(module) do
    case Code.ensure_compiled(module) do
      {:module, _module} ->
        :ok

      {:error, :nofile} ->
        # Compiled inline, for example inside a test. Nothing to wait for.
        :ok

      {:error, reason} ->
        raise ArgumentError, "could not load module #{inspect(module)} due to reason #{inspect(reason)}"
    end
  end
end
