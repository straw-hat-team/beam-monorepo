if Code.ensure_loaded?(:telemetry) do
  defmodule Trogon.Test.TestTelemetry do
    @moduledoc """
    Helpers that assert on the `:telemetry` events a test caused.

    Available when the project depends on `:telemetry`.

    A `:telemetry` handler is global: it runs for every process that emits the
    event, so a handler that forwards events to a test also forwards the events
    every other concurrent test emits. `attach/1` forwards only the events the
    test process emits, or a process with the test in its `$callers`, such as a
    `Task`, and detaches when the test exits:

        use Trogon.Test

        test "reports the charge" do
          TestTelemetry.attach([[:my_app, :billing, :charge]])

          MyApp.Billing.charge(100)

          TestTelemetry.assert_receive_event([:my_app, :billing, :charge], %{amount: 100}, _metadata)
        end

    Events go to the test's mailbox under their own tag, so
    `Trogon.Test.assert_empty_mailbox/0` and
    `Trogon.Test.verify_mailbox_on_exit!/1` never count them.
    """

    @doc """
    Forwards each event in `event_names` that the test, or a process with the
    test in its `$callers`, emits to the test's mailbox until the test exits.
    """
    @spec attach([:telemetry.event_name()]) :: :ok
    def attach(event_names) do
      handler_id = {__MODULE__, make_ref()}
      :ok = :telemetry.attach_many(handler_id, event_names, &__MODULE__.handle_event/4, self())
      ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    @doc false
    @spec handle_event(:telemetry.event_name(), map(), map(), pid()) :: :ok
    def handle_event(event_name, measurements, metadata, test) do
      if self() == test or test in Process.get(:"$callers", []) do
        send(test, {__MODULE__, event_name, measurements, metadata})
      end

      :ok
    end

    @doc """
    Asserts an event matching the patterns arrives within the `assert_receive`
    timeout, and returns it.
    """
    defmacro assert_receive_event(event_name, measurements, metadata) do
      quote do
        ExUnit.Assertions.assert_receive(
          {Trogon.Test.TestTelemetry, unquote(event_name), unquote(measurements), unquote(metadata)}
        )
      end
    end

    @doc """
    Asserts an event matching the patterns arrives within `timeout`
    milliseconds, and returns it.
    """
    defmacro assert_receive_event(event_name, measurements, metadata, timeout) do
      quote do
        ExUnit.Assertions.assert_receive(
          {Trogon.Test.TestTelemetry, unquote(event_name), unquote(measurements), unquote(metadata)},
          unquote(timeout)
        )
      end
    end

    @doc """
    Asserts no event matching the patterns has arrived.
    """
    defmacro refute_received_event(event_name, measurements, metadata) do
      quote do
        ExUnit.Assertions.refute_received(
          {Trogon.Test.TestTelemetry, unquote(event_name), unquote(measurements), unquote(metadata)}
        )
      end
    end
  end
end
