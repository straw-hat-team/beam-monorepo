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
        Mox.expect(MyApp.DispatcherMock, :dispatch_command, fn %RegisterUser{}, _options ->
          {:ok, %User{id: 1}}
        end)
      end

  Mock at the dispatcher boundary. There is no per-command handler stubbing, by design.

  ## Importing

  The assertion helpers are macros, so import the module (or `require` it) before using them:

      defmodule MyApp.DispatcherTest do
        use ExUnit.Case, async: true

        import Trogon.Dispatcher.Test
      end
  """

  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchOptions

  @telemetry_tag :trogon_dispatcher_telemetry

  @doc """
  Builds a `Trogon.Dispatcher.Context` for testing a middleware or a handler in isolation.

  `overrides` accepts `:kind`, `:dispatcher`, `:registered_by` and `:private`.

  ## Example

      context = Test.build_context(%RegisterUser{email: "a@b.c"}, %DispatchOptions{actor: actor}, kind: :command)
  """
  @spec build_context(struct(), DispatchOptions.t(), keyword()) :: Context.t()
  def build_context(command, options \\ %DispatchOptions{}, overrides \\ []) do
    overrides = Keyword.put_new(overrides, :dispatcher, __MODULE__)
    Context.new(command, options, overrides)
  end

  @doc """
  Runs a single middleware against a context and a `next` of your choosing.

  `init/1` runs first, exactly as it would at compile time. The return value is the context the middleware produced,
  so assert on `context.response`, `context.assigns` or `context.private`. `next` defaults to a function that puts
  `:ok` as the response, so a middleware that only inspects the context needs nothing more than the context.

  ## Example

      context = Test.call_middleware(MyApp.Authorize, [], Test.build_context(command))
      assert context.response == {:error, :unauthorized}

      context =
        Test.call_middleware(MyApp.Authorize, [], context, fn ctx ->
          send(self(), {:reached, ctx})
          Context.put_response(ctx, :ok)
        end)
  """
  @spec call_middleware(module(), term(), Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def call_middleware(
        middleware_mod,
        options \\ [],
        %Context{} = context,
        next \\ &Context.put_response(&1, :ok)
      ) do
    initialized =
      if Code.ensure_loaded?(middleware_mod) and function_exported?(middleware_mod, :init, 1) do
        middleware_mod.init(options)
      else
        options
      end

    middleware_mod.call(context, next, initialized)
  end

  @doc """
  Forwards every dispatch event under `prefix` to the calling process and detaches on test exit.

  Messages arrive as `{:trogon_dispatcher_telemetry, phase, event, measurements, metadata}` where `phase` is
  `:start`, `:stop` or `:exception`.

  Only events emitted *in the calling process* are forwarded. Dispatch is synchronous and in-process, so this keeps
  `async: true` test modules from seeing each other's events. A dispatch you deliberately run in another process will
  not be forwarded.

  ## Example

      setup do
        Test.attach_telemetry!([:my_app, :dispatcher])
        :ok
      end
  """
  @spec attach_telemetry!([atom()]) :: :ok
  def attach_telemetry!(prefix \\ [:trogon_dispatcher]) do
    test_process = self()
    handler_id = {__MODULE__, prefix, test_process, System.unique_integer()}

    events = for phase <- [:start, :stop, :exception], do: prefix ++ [:dispatch, phase]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.__forward__/4,
        test_process
      )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler_id) end)

    :ok
  end

  @doc false
  def __forward__(event, measurements, metadata, test_process) do
    if self() == test_process do
      send(test_process, {@telemetry_tag, List.last(event), event, measurements, metadata})
    end

    :ok
  end

  @doc """
  Asserts that a dispatch of `command_mod` started, and returns the start metadata.
  """
  defmacro assert_dispatch_start(command_mod) do
    quote do
      ExUnit.Assertions.assert_receive(
        {unquote(@telemetry_tag), :start, _event, _measurements, %{command: unquote(command_mod)} = metadata}
      )

      metadata
    end
  end

  @doc """
  Asserts that a dispatch of `command_mod` completed, and returns the stop metadata.

  The stop metadata carries `:result` (`:ok` or `:error`) and, on failure, `:error`.

  ## Example

      metadata = Test.assert_dispatch_stop(RegisterUser)
      assert metadata.result == :ok
      assert metadata.registered_by == MyApp.Accounts.Dispatcher
  """
  defmacro assert_dispatch_stop(command_mod) do
    quote do
      ExUnit.Assertions.assert_receive(
        {unquote(@telemetry_tag), :stop, _event, _measurements, %{command: unquote(command_mod)} = metadata}
      )

      metadata
    end
  end

  @doc """
  Asserts that a dispatch of `command_mod` raised, and returns the exception metadata.
  """
  defmacro assert_dispatch_exception(command_mod) do
    quote do
      ExUnit.Assertions.assert_receive(
        {unquote(@telemetry_tag), :exception, _event, _measurements, %{command: unquote(command_mod)} = metadata}
      )

      metadata
    end
  end

  @doc """
  Refutes that any dispatch of `command_mod` was started.
  """
  defmacro refute_dispatch(command_mod) do
    quote do
      ExUnit.Assertions.refute_receive(
        {unquote(@telemetry_tag), :start, _event, _measurements, %{command: unquote(command_mod)}}
      )
    end
  end
end
