defmodule Trogon.Dispatcher.Test do
  @moduledoc """
  Test helpers for dispatchers, middleware, and the telemetry a dispatch emits.

  This module always ships. It is not gated on `Mix.env()`, because Mix compiles dependencies with `env: :prod` by
  default, so an env-gated module would simply not exist for anyone depending on this package. Tesla ships
  `Tesla.Mock` in `lib/` for the same reason.

  ## Mocking a dispatcher

  Every dispatcher declares its own callbacks, so it is already a behaviour and needs no companion module:

      Mox.defmock(MyApp.DispatcherMock, for: MyApp.Dispatcher)

      test "registers the user" do
        Test.expect_dispatch(MyApp.DispatcherMock, RegisterUser, returns: {:ok, %User{id: 1}})

        # ... exercise the code under test ...

        Test.assert_dispatched(%RegisterUser{}, %DispatchOptions{})
      end

  Mock at the dispatcher boundary: it is the seam your application code depends on, so it is the seam worth
  faking. There is deliberately no per-message handler stubbing.

  `expect_dispatch/3` and `assert_dispatched/2` only exist when `Mox` is loaded. A plain `Mox.expect/4` still works,
  but it lets a mock return a response no real dispatch could, so the test passes where production would raise.

  ## Requiring

  The assertion helpers are macros, so require the module before using them:

      defmodule MyApp.DispatcherTest do
        use ExUnit.Case, async: true

        alias Trogon.Dispatcher.Test

        require Test
      end
  """

  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchOptions

  @telemetry_tag __MODULE__

  @doc """
  Builds a `Trogon.Dispatcher.Context` for testing a middleware or a handler in isolation.

  `overrides` accepts `:kind`, `:dispatcher`, `:registered_by` and `:private`.

  ## Example

      context = Test.build_context(%RegisterUser{email: "a@b.c"}, %DispatchOptions{actor: actor}, kind: :command)
  """
  @spec build_context(struct(), DispatchOptions.t(), keyword()) :: Context.t()
  def build_context(message, options \\ %DispatchOptions{}, overrides \\ []) do
    overrides = Keyword.put_new(overrides, :dispatcher, __MODULE__)
    Context.new(message, options, overrides)
  end

  @doc """
  Runs a handler against a context, the way a dispatch would.

  The handler receives `context.message` and the context itself, and its return value is held to the response
  contract in `Trogon.Dispatcher.Handler`: anything outside it raises `Trogon.Dispatcher.InvalidResponseError`, just
  as it would in production. The return value is the handler's response.

  ## Example

      context = Test.build_context(%RegisterUser{email: "a@b.c"}, %DispatchOptions{actor: actor}, kind: :command)
      assert {:ok, %User{}} = Test.call_handler(MyApp.Accounts.RegisterUser, context)
  """
  @spec call_handler(module(), Context.t()) :: Trogon.Dispatcher.response()
  def call_handler(handler_mod, %Context{} = context) when is_atom(handler_mod) do
    returned = handler_mod.handle_message(context.message, context)
    Trogon.Dispatcher.validate_response(returned, handler_mod, context).response
  end

  @doc """
  Runs a single middleware against a context.

  `init/1` runs first, exactly as it would at compile time. The return value is the context the middleware produced,
  so assert on `context.response`, `context.assigns` or `context.private`. Returning anything other than a context
  raises `Trogon.Dispatcher.InvalidContextError`, and a response outside the contract in `Trogon.Dispatcher.Handler`
  raises `Trogon.Dispatcher.InvalidResponseError`, just as they would in production.

  ## Options

    * `:options` - what `middleware MyMiddleware, options` would pass to `init/1`. Defaults to `[]`.
    * `:next` - the rest of the pipeline. Defaults to a function that puts `:ok` as the response, so a middleware that
      only inspects the context needs nothing more than the context.

  ## Example

      context = Test.call_middleware(MyApp.Authorize, Test.build_context(message), options: [role: :admin])
      assert context.response == {:error, :unauthorized}

      context =
        Test.call_middleware(MyApp.Authorize, context,
          options: [role: :admin],
          next: fn ctx ->
            send(self(), {:reached, ctx})
            Context.put_response(ctx, :ok)
          end
        )
  """
  @spec call_middleware(module(), Context.t(), keyword()) :: Context.t()
  def call_middleware(middleware_mod, %Context{} = context, opts \\ []) do
    opts = Keyword.validate!(opts, options: [], next: &Context.put_response(&1, :ok))
    options = Keyword.fetch!(opts, :options)

    initialized =
      if Code.ensure_loaded?(middleware_mod) do
        Trogon.Dispatcher.initialize_middleware!(middleware_mod, options)
      else
        options
      end

    context
    |> middleware_mod.call(Keyword.fetch!(opts, :next), initialized)
    |> Trogon.Dispatcher.validate(middleware_mod, context)
  end

  if Code.ensure_loaded?(Mox) do
    @doc """
    Expects `mock` to dispatch a `message_mod` message, using `Mox.expect/4`.

    The expectation covers every entry point a real dispatcher has: `dispatch_message/1` and `dispatch_message!/1,2`
    are stubbed to route through the expected `dispatch_message/2`, so the test does not depend on which one the code
    under test calls. The bang variants unwrap the response exactly as a real dispatcher does.

    The mocked response is held to the contract in `Trogon.Dispatcher.Handler`, so a response no real dispatch could
    produce raises `Trogon.Dispatcher.InvalidResponseError`. Every call is sent to the test process for
    `assert_dispatched/2`.

    Expectations are consumed in the order they are declared, as with `Mox.expect/4`. A dispatched message that is
    not a `message_mod` fails the test rather than falling through to the next expectation.

    ## Options

      * `:returns` - the response, such as `:ok`, `{:ok, %User{}}` or `{:error, :taken}`, or a function receiving
        the message and the `Trogon.Dispatcher.DispatchOptions` that returns one. Defaults to `:ok`.
      * `:times` - how many dispatches to expect. Defaults to `1`.

    ## Examples

        Test.expect_dispatch(MyApp.DispatcherMock, ArchiveUser)

        Test.expect_dispatch(MyApp.DispatcherMock, RegisterUser, returns: {:ok, %User{email: "a@b.c"}})

        Test.expect_dispatch(MyApp.DispatcherMock, RegisterUser,
          returns: fn %RegisterUser{email: email}, _options -> {:ok, %User{email: email}} end
        )
    """
    @spec expect_dispatch(module(), module(), keyword()) :: module()
    def expect_dispatch(mock, message_mod, opts \\ []) when is_atom(mock) and is_atom(message_mod) do
      opts = Keyword.validate!(opts, returns: :ok, times: 1)
      returns = Keyword.fetch!(opts, :returns)
      test_process = self()

      Mox.expect(mock, :dispatch_message, Keyword.fetch!(opts, :times), fn message, options ->
        verify_dispatch!(mock, message_mod, message, options)
        send(test_process, {@telemetry_tag, :dispatched, mock, message, options})

        message
        |> mocked_response(options, returns)
        |> Trogon.Dispatcher.validate_response(mock, Context.new(message, options, dispatcher: mock))
        |> Map.fetch!(:response)
      end)

      mock
      |> Mox.stub(:dispatch_message, fn message -> mock.dispatch_message(message, %DispatchOptions{}) end)
      |> Mox.stub(:dispatch_message!, fn message -> mock.dispatch_message!(message, %DispatchOptions{}) end)
      |> Mox.stub(:dispatch_message!, fn message, options ->
        message |> mock.dispatch_message(options) |> Trogon.Dispatcher.unwrap(message, mock)
      end)
    end

    defp verify_dispatch!(mock, message_mod, message, options) do
      if not is_struct(message, message_mod) do
        ExUnit.Assertions.flunk("""
        expected #{inspect(mock)} to dispatch #{inspect(message_mod)}, got: #{inspect(message)}

        Expectations are consumed in the order they are declared.
        """)
      end

      if not is_struct(options, DispatchOptions) do
        raise ArgumentError,
              "expected a %#{inspect(DispatchOptions)}{} as the second argument, got: #{inspect(options)}"
      end
    end

    defp mocked_response(message, options, returns) when is_function(returns, 2), do: returns.(message, options)
    defp mocked_response(_message, _options, returns), do: returns

    @doc """
    Asserts that a mock set up with `expect_dispatch/3` received a dispatch matching `message` and `options`.

    Both arguments are patterns, and variables they bind are available after the assertion.

    ## Example

        Test.assert_dispatched(%RegisterUser{email: email}, %DispatchOptions{actor: %User{}})
        assert email == "a@b.c"
    """
    defmacro assert_dispatched(message, options \\ quote(do: _)) do
      quote do
        ExUnit.Assertions.assert_received(
          {unquote(@telemetry_tag), :dispatched, _mock, unquote(message), unquote(options)}
        )
      end
    end
  end

  @doc """
  Forwards every dispatch event to the calling process and detaches on test exit.

  Messages arrive as `{Trogon.Dispatcher.Test, phase, event, measurements, metadata}` where `phase` is
  `:start`, `:stop` or `:exception`.

  Only events emitted *in the calling process* are forwarded. Dispatch is synchronous and in-process, so this keeps
  `async: true` test modules from seeing each other's events. A dispatch you deliberately run in another process will
  not be forwarded.

  ## Example

      setup do
        Test.attach_telemetry!()
        :ok
      end
  """
  @spec attach_telemetry!() :: :ok
  def attach_telemetry! do
    test_process = self()
    handler_id = {__MODULE__, test_process, System.unique_integer()}

    events = for phase <- [:start, :stop, :exception], do: [:trogon_dispatcher, :dispatch, phase]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.forward_telemetry/4,
        test_process
      )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  @doc false
  def forward_telemetry(event, measurements, metadata, test_process) do
    if self() == test_process do
      send(test_process, {@telemetry_tag, List.last(event), event, measurements, metadata})
    end

    :ok
  end

  @doc """
  Asserts that a dispatch of `message_mod` started, and returns the start metadata.
  """
  defmacro assert_dispatch_start(message_mod) do
    quote do
      ExUnit.Assertions.assert_receive(
        {unquote(@telemetry_tag), :start, _event, _measurements, %{message: unquote(message_mod)} = metadata}
      )

      metadata
    end
  end

  @doc """
  Asserts that a dispatch of `message_mod` completed, and returns the stop metadata.

  The stop metadata carries `:result` (`:ok` or `:error`) and, on failure, `:error`.

  ## Example

      metadata = Test.assert_dispatch_stop(RegisterUser)
      assert metadata.result == :ok
      assert metadata.registered_by == MyApp.Accounts.Dispatcher
  """
  defmacro assert_dispatch_stop(message_mod) do
    quote do
      ExUnit.Assertions.assert_receive(
        {unquote(@telemetry_tag), :stop, _event, _measurements, %{message: unquote(message_mod)} = metadata}
      )

      metadata
    end
  end

  @doc """
  Asserts that a dispatch of `message_mod` raised, and returns the exception metadata.
  """
  defmacro assert_dispatch_exception(message_mod) do
    quote do
      ExUnit.Assertions.assert_receive(
        {unquote(@telemetry_tag), :exception, _event, _measurements, %{message: unquote(message_mod)} = metadata}
      )

      metadata
    end
  end

  @doc """
  Refutes that any dispatch of `message_mod` was started.
  """
  defmacro refute_dispatch(message_mod) do
    quote do
      ExUnit.Assertions.refute_receive(
        {unquote(@telemetry_tag), :start, _event, _measurements, %{message: unquote(message_mod)}}
      )
    end
  end
end
