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
        use Trogon.Dispatcher, telemetry_prefix: [:my_app, :dispatcher]

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
  it inherited.

  Reaching the same registration twice through a diamond of imports dedupes silently. Two paths that disagree on the
  handler, the kind, or the effective middleware chain raise `Trogon.Dispatcher.DuplicateMessageError` at compile time.

  ## Generated API

  Each dispatcher gets `dispatch_message/1`, `dispatch_message/2`, `dispatch_message!/1` and `dispatch_message!/2`,
  declared as callbacks on the dispatcher module itself. That makes every dispatcher a behaviour, so a host injects
  the module and mocks it with `Mox.defmock(MyApp.DispatcherMock, for: MyApp.Dispatcher)` without a separate
  behaviour module.

  It also gets `__trogon_dispatcher__/1` for introspection, which is what `import_dispatcher` reads.
  """

  alias Trogon.Dispatcher.CircularImportError
  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchError
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.DuplicateMessageError
  alias Trogon.Dispatcher.InvalidContextError
  alias Trogon.Dispatcher.InvalidResponseError
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

  @default_telemetry_prefix [:trogon_dispatcher]

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import Trogon.Dispatcher,
        only: [middleware: 1, middleware: 2, register_message: 2, import_dispatcher: 1]

      @trogon_dispatcher_telemetry_prefix Trogon.Dispatcher.__telemetry_prefix__(opts)

      Module.register_attribute(__MODULE__, :trogon_dispatcher_middleware, accumulate: true)
      Module.register_attribute(__MODULE__, :trogon_dispatcher_registrations, accumulate: true)
      Module.register_attribute(__MODULE__, :trogon_dispatcher_imported, accumulate: true)
      Module.register_attribute(__MODULE__, :trogon_dispatcher_imports, accumulate: true)

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
      Trogon.Dispatcher.__register_message__(__MODULE__, message_mod, opts)
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
      Trogon.Dispatcher.__import_dispatcher__(__MODULE__, dispatcher_mod)
    end
  end

  defmacro __before_compile__(env) do
    module = env.module
    options_mod = DispatchOptions
    unregistered_mod = UnregisteredMessageError

    local_middleware = __accumulated__(module, :trogon_dispatcher_middleware)
    imports = __accumulated__(module, :trogon_dispatcher_imports)
    local_registrations = __local_registrations__(module)
    imported_registrations = __accumulated__(module, :trogon_dispatcher_imported)

    registrations =
      __resolve_registrations__(module, local_middleware, local_registrations ++ imported_registrations)

    telemetry_prefix = Module.get_attribute(module, :trogon_dispatcher_telemetry_prefix)
    event = telemetry_prefix ++ [:dispatch]

    indexed = Enum.with_index(registrations)
    clauses = Enum.map(indexed, &__dispatch_clause__(&1, event, Context, options_mod))
    stages = Enum.flat_map(indexed, &__stage_functions__/1)

    quote do
      unquote(__introspection__(registrations, local_middleware, imports, telemetry_prefix))
      unquote(__entrypoints__(options_mod))
      unquote(clauses)
      unquote(__fallbacks__(options_mod, unregistered_mod))
      unquote(stages)
    end
  end

  defp __introspection__(registrations, local_middleware, imports, telemetry_prefix) do
    quote do
      @doc false
      def __trogon_dispatcher__(:registrations), do: unquote(Macro.escape(registrations))
      def __trogon_dispatcher__(:middleware), do: unquote(Macro.escape(local_middleware))
      def __trogon_dispatcher__(:imports), do: unquote(Macro.escape(imports))
      def __trogon_dispatcher__(:telemetry_prefix), do: unquote(telemetry_prefix)
    end
  end

  defp __entrypoints__(options_mod) do
    quote do
      def dispatch_message(message, options \\ %unquote(options_mod){})
      def dispatch_message!(message, options \\ %unquote(options_mod){})

      def dispatch_message!(message, options) do
        message
        |> dispatch_message(options)
        |> Trogon.Dispatcher.__unwrap__(message, __MODULE__)
      end
    end
  end

  defp __fallbacks__(options_mod, unregistered_mod) do
    quote do
      def dispatch_message(message, %unquote(options_mod){}) do
        {:error, unquote(unregistered_mod).exception(dispatched_message: message, dispatcher: __MODULE__)}
      end

      def dispatch_message(_message, options) do
        raise ArgumentError,
              "expected a %#{inspect(unquote(options_mod))}{} as the second argument, got: #{inspect(options)}"
      end
    end
  end

  defp __accumulated__(module, attribute) do
    module |> Module.get_attribute(attribute) |> Enum.reverse()
  end

  defp __local_registrations__(module) do
    for {message_mod, handler_mod, kind} <- __accumulated__(module, :trogon_dispatcher_registrations) do
      %{message: message_mod, handler: handler_mod, kind: kind, registered_by: module, middleware: []}
    end
  end

  @doc false
  def __unwrap__(:ok, _message, _dispatcher), do: :ok
  def __unwrap__({:ok, value}, _message, _dispatcher), do: value
  def __unwrap__({:error, reason}, message, dispatcher), do: __raise__(reason, message, dispatcher)

  @doc false
  def __after_verify__(module) do
    for registration <- module.__trogon_dispatcher__(:registrations) do
      __verify_handler__(module, registration)
    end

    :ok
  end

  @doc false
  def __telemetry_prefix__(opts) do
    prefix = Keyword.get(opts, :telemetry_prefix, @default_telemetry_prefix)

    if not (is_list(prefix) and prefix != [] and Enum.all?(prefix, &is_atom/1)) do
      raise ArgumentError,
            "expected :telemetry_prefix to be a non-empty list of atoms, got: #{inspect(prefix)}"
    end

    prefix
  end

  @doc false
  def __middleware__(module, middleware_mod, opts) do
    __ensure_compiled__!(middleware_mod)

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

    initialized =
      if function_exported?(middleware_mod, :init, 1) do
        middleware_mod.init(opts)
      else
        opts
      end

    Module.put_attribute(module, :trogon_dispatcher_middleware, {middleware_mod, initialized})
  end

  @doc false
  def __register_message__(module, message_mod, opts) do
    __ensure_compiled__!(message_mod)

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

    if not __struct_module__?(message_mod) do
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

    Module.put_attribute(module, :trogon_dispatcher_registrations, {message_mod, handler_mod, kind})
  end

  @doc false
  def __import_dispatcher__(module, dispatcher_mod) do
    if module == dispatcher_mod do
      raise CircularImportError.exception(
              dispatcher: module,
              imported: dispatcher_mod,
              path: [module, dispatcher_mod]
            )
    end

    __ensure_compiled__!(dispatcher_mod)

    if not __dispatcher__?(dispatcher_mod) do
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

    __check_cycle__!(module, dispatcher_mod)

    Module.put_attribute(module, :trogon_dispatcher_imports, dispatcher_mod)

    for registration <- dispatcher_mod.__trogon_dispatcher__(:registrations) do
      Module.put_attribute(module, :trogon_dispatcher_imported, registration)
    end

    :ok
  end

  @doc false
  def __resolve_registrations__(module, local_middleware, registrations) do
    registrations
    |> Enum.map(fn registration ->
      %{registration | middleware: Enum.uniq(local_middleware ++ registration.middleware)}
    end)
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

  @doc false
  def __dispatch_clause__({registration, index}, event, context_mod, options_mod) do
    entry = __stage_name__(index, 0)

    quote do
      def dispatch_message(%unquote(registration.message){} = message, %unquote(options_mod){} = options) do
        context = %unquote(context_mod){
          message: message,
          kind: unquote(registration.kind),
          dispatcher: __MODULE__,
          registered_by: unquote(registration.registered_by),
          correlation_id: options.correlation_id,
          causation_id: options.causation_id,
          actor: options.actor,
          assigns: options.assigns,
          private: %{}
        }

        metadata = %{
          message: unquote(registration.message),
          kind: unquote(registration.kind),
          dispatcher: __MODULE__,
          registered_by: unquote(registration.registered_by),
          context: context
        }

        :telemetry.span(unquote(event), metadata, fn ->
          final = unquote(entry)(context)
          {final.response, Trogon.Dispatcher.__stop_metadata__(metadata, final)}
        end)
      end
    end
  end

  @doc false
  def __stage_functions__({registration, index}) do
    middleware_stages =
      registration.middleware
      |> Enum.with_index()
      |> Enum.map(fn {{middleware_mod, options}, step} ->
        name = __stage_name__(index, step)
        next = __capture__(__stage_name__(index, step + 1))

        quote do
          defp unquote(name)(context) do
            Trogon.Dispatcher.__validate__(
              unquote(middleware_mod).call(context, unquote(next), unquote(Macro.escape(options))),
              unquote(middleware_mod),
              context
            )
          end
        end
      end)

    handler_stage =
      quote do
        defp unquote(__stage_name__(index, length(registration.middleware)))(context) do
          Trogon.Dispatcher.__validate_response__(
            unquote(registration.handler).handle_message(context.message, context),
            unquote(registration.handler),
            context
          )
        end
      end

    middleware_stages ++ [handler_stage]
  end

  @doc false
  def __validate__(%Context{} = returned, module, _context) do
    __validate_response__(returned.response, module, returned)
  end

  def __validate__(returned, module, context) do
    raise InvalidContextError.exception(
            module: module,
            dispatched_message: context.message,
            dispatcher: context.dispatcher,
            returned: returned
          )
  end

  @doc false
  def __validate_response__(:ok, _module, context), do: %{context | response: :ok}

  def __validate_response__({:ok, value} = response, _module, context) when is_struct(value) do
    %{context | response: response}
  end

  def __validate_response__({:error, _reason} = response, _module, context) do
    %{context | response: response}
  end

  def __validate_response__(response, module, context) do
    raise InvalidResponseError.exception(
            module: module,
            dispatched_message: context.message,
            dispatcher: context.dispatcher,
            response: response
          )
  end

  @doc false
  def __stop_metadata__(metadata, %Context{} = context) do
    metadata |> Map.put(:context, context) |> __result_metadata__(context.response)
  end

  defp __result_metadata__(metadata, :ok), do: Map.put(metadata, :result, :ok)
  defp __result_metadata__(metadata, {:ok, _value}), do: Map.put(metadata, :result, :ok)

  defp __result_metadata__(metadata, {:error, reason}) do
    metadata |> Map.put(:result, :error) |> Map.put(:error, reason)
  end

  @doc false
  def __raise__(reason, _message, _dispatcher) when is_exception(reason) do
    raise reason
  end

  def __raise__(reason, message, dispatcher) do
    raise DispatchError.exception(reason: reason, dispatched_message: message, dispatcher: dispatcher)
  end

  defp __verify_handler__(module, registration) do
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

  defp __check_cycle__!(module, dispatcher_mod) do
    path = __import_path__(dispatcher_mod, module, [dispatcher_mod], [])

    if path do
      raise CircularImportError.exception(
              dispatcher: module,
              imported: dispatcher_mod,
              path: [module | path]
            )
    end
  end

  defp __import_path__(current, target, acc, seen) do
    cond do
      current == target ->
        Enum.reverse(acc)

      current in seen ->
        nil

      not __dispatcher__?(current) ->
        nil

      true ->
        seen = [current | seen]

        Enum.find_value(current.__trogon_dispatcher__(:imports), fn imported ->
          __import_path__(imported, target, [imported | acc], seen)
        end)
    end
  end

  defp __stage_name__(index, step), do: :"__trogon_dispatcher_stage_#{index}_#{step}__"

  defp __capture__(name), do: {:&, [], [{:/, [], [{name, [], nil}, 1]}]}

  defp __dispatcher__?(module) do
    function_exported?(module, :__trogon_dispatcher__, 1)
  end

  defp __struct_module__?(module) do
    function_exported?(module, :__struct__, 0)
  end

  defp __ensure_compiled__!(module) do
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
