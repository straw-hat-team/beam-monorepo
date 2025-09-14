defmodule Trogon.Commanded.TestSupport.CommandHandlerCase do
  @moduledoc ~S"""
  This module helps with test cases for testing aggregate states, and command handlers.

  ## Options

  - `aggregate`: The aggregate module to use in the command handler case. If not provided, then you must provide a
    `handler` option.
  - `handler`: The command handler module to use in the command handler case. If the `aggregate` option is not provided,
    then the `Handler.Aggregate` module will be used as the aggregate module. Read more about transaction script
    command handler at `Trogon.Commanded.CommandRouter.register_transaction_script/2`.

  ## Usage

  After import the test support file, you should be able to have the module in your test files.

      defmodule MyAggregateTest do
        use Trogon.Commanded.TestSupport.CommandHandlerCase,
          handler: MyCommandHandler,
          async: true

        describe "my aggregate" do
          test "should do something" do
            assert_events(
              [%InitialEvent{}],
              %DoSomething{},
              [%SomethingHappened{}]
            )
          end

          test "the state" do
            assert_state(
              [%InitialEvent{}],
              %DoSomething{},
              %MyAggregate{}
            )
          end

          test "the error" do
            assert_error(
              [%InitialEvent{}],
              %DoSomething{},
              :already_exists
            )
          end
        end
      end
  """

  use ExUnit.CaseTemplate

  alias Commanded.Aggregate.Multi
  alias Commanded.Middleware.Pipeline
  alias Commanded.Middleware.ExtractAggregateIdentity
  alias Trogon.Commanded.TestSupport.CommandHandlerCase

  using opts do
    quote do
      opts = unquote(opts)

      if opts[:aggregate] == nil && opts[:handler] == nil do
        raise "Trogon.Commanded.TestSupport.CommandHandlerCase: you must provide at least `aggregate` or `handler`"
      end

      aggregate =
        Keyword.get_lazy(opts, :aggregate, fn ->
          if opts[:handler] do
            Module.concat([opts[:handler], "Aggregate"])
          else
            raise "Trogon.Commanded.TestSupport.CommandHandlerCase: `handler` is required when `aggregate` is not provided"
          end
        end)

      handler = Keyword.get(opts, :handler, nil)

      @aggregate aggregate
      @handler handler

      defp assert_events(initial_events, command, expected_events) do
        CommandHandlerCase.assert_events(
          initial_events,
          command,
          expected_events,
          @aggregate,
          @handler
        )
      end

      defp assert_state(initial_events, command, expected_state) do
        CommandHandlerCase.assert_state(
          initial_events,
          command,
          expected_state,
          @aggregate,
          @handler
        )
      end

      defp assert_error(initial_events, command, expected_error) do
        CommandHandlerCase.assert_error(
          initial_events,
          command,
          expected_error,
          @aggregate,
          @handler
        )
      end
    end
  end

  def assert_events(
        initial_events,
        command,
        expected_events,
        aggregate_module,
        command_handler_module
      ) do
    assert {:ok, _state, events} =
             aggregate_run(
               aggregate_module,
               command_handler_module,
               initial_events,
               command
             )

    actual_events = List.wrap(events)
    expected_events = List.wrap(expected_events)

    assert actual_events == expected_events
  end

  def assert_state(
        initial_events,
        command,
        expected_state,
        aggregate_module,
        command_handler_module
      ) do
    assert {:ok, state, _events} =
             aggregate_run(
               aggregate_module,
               command_handler_module,
               initial_events,
               command
             )

    assert state == expected_state
  end

  def assert_error(
        initial_events,
        command,
        expected_error,
        aggregate_module,
        command_handler_module
      ) do
    assert {:error, reason} =
             aggregate_run(
               aggregate_module,
               command_handler_module,
               initial_events,
               command
             )

    assert reason == expected_error
  end

  defp aggregate_run(aggregate_module, command_handler_module, initial_events, command) do
    evolver = &aggregate_module.apply/2

    decider =
      if command_handler_module == nil,
        do: &aggregate_module.execute/2,
        else: &command_handler_module.handle/2

    # Extract the real aggregate identity using the same middleware as production
    aggregate_uuid = extract_aggregate_identity(command, aggregate_module)
    assert aggregate_uuid, "aggregate_uuid must never be nil for aggregates with identity configuration"

    result =
      aggregate_module
      |> struct()
      |> evolve(initial_events, evolver)
      |> execute(command, evolver, decider)

    # Transform the result to use the real aggregate identity (only if we have one)
    case result do
      {:ok, state, events} when not is_nil(aggregate_uuid) ->
        transformed_events = transform_event_identities(events, aggregate_uuid, aggregate_module)
        transformed_state = transform_aggregate_identity(state, aggregate_uuid, aggregate_module)
        {:ok, transformed_state, transformed_events}

      {:ok, _state, _events} when is_nil(aggregate_uuid) ->
        # This should only happen for simple test fixtures without identity configuration
        # If we reach here with a real Trogon.Commanded.Aggregate, something is wrong
        result

      # No transformation for simple test fixtures or when no identity config
      other ->
        other
    end
  end

  defp execute(state, command, evolver, decider) do
    try do
      {new_state, events} =
        state
        |> decider.(command)
        |> process_response()
        |> maybe_evolve(state, evolver)

      {:ok, new_state, events}
    catch
      {:error, _error} = reply -> reply
    end
  end

  defp process_response({:error, _error} = error) do
    throw(error)
  end

  defp process_response(%Multi{} = multi) do
    case Multi.run(multi) do
      {:error, _reason} = error ->
        throw(error)

      {state, events} ->
        {state, events}
    end
  end

  defp process_response(no_events) when no_events in [:ok, nil, []] do
    []
  end

  defp process_response({:ok, events}) do
    events
  end

  defp process_response(events) when is_list(events) do
    events
  end

  defp process_response(event) when is_map(event) do
    [event]
  end

  defp process_response(invalid) do
    flunk("unexpected: " <> inspect(invalid))
  end

  defp maybe_evolve({state, events} = _multi_response, _state, _evolver) do
    {state, events}
  end

  defp maybe_evolve(events, state, evolver) do
    {evolve(state, events, evolver), events}
  end

  defp evolve(state, events, evolver) do
    events
    |> List.wrap()
    |> Enum.reduce(state, &evolver.(&2, &1))
  end

  defp extract_aggregate_identity(command, aggregate_module) do
    # Follow the same pattern as CommandRouter:
    # 1. Try command module first (for transaction scripts)
    # 2. Fall back to aggregate module (for regular aggregates)
    command_module = command.__struct__

    {identifier, identity_prefix} =
      if function_exported?(command_module, :aggregate_identifier, 0) and
           function_exported?(command_module, :identity_prefix, 0) do
        # Transaction script pattern - use command module's configuration
        {command_module.aggregate_identifier(), command_module.identity_prefix()}
      else
        # Regular aggregate pattern - use aggregate module's configuration
        {get_identifier(aggregate_module), get_identity_prefix(aggregate_module)}
      end

    # Create a pipeline like Commanded does in production
    pipeline = %Pipeline{
      command: command,
      identity: identifier,
      identity_prefix: identity_prefix
    }

    # Let ExtractAggregateIdentity middleware handle everything
    case ExtractAggregateIdentity.before_dispatch(pipeline) do
      %Pipeline{assigns: %{aggregate_uuid: uuid}} -> uuid
      # No transformation applied
      %Pipeline{} -> nil
    end
  end

  defp get_identity_prefix(aggregate_module) do
    if function_exported?(aggregate_module, :identity_prefix, 0) do
      aggregate_module.identity_prefix()
    else
      # No prefix
      nil
    end
  end

  defp transform_event_identities(events, aggregate_uuid, aggregate_module) do
    identifier = get_identifier(aggregate_module)

    events
    |> List.wrap()
    |> Enum.map(fn event ->
      # Only transform if the event has the identifier field and the UUID is different
      if Map.has_key?(event, identifier) and Map.get(event, identifier) != aggregate_uuid do
        Map.put(event, identifier, aggregate_uuid)
      else
        # Return unchanged if no identifier field or already correct
        event
      end
    end)
  end

  defp transform_aggregate_identity(state, aggregate_uuid, aggregate_module) do
    identifier = get_identifier(aggregate_module)

    # Only transform if the state has the identifier field and the UUID is different
    if Map.has_key?(state, identifier) and Map.get(state, identifier) != aggregate_uuid do
      Map.put(state, identifier, aggregate_uuid)
    else
      # Return unchanged if no identifier field or already correct
      state
    end
  end

  defp get_identifier(aggregate_module) do
    if function_exported?(aggregate_module, :identifier, 0) do
      aggregate_module.identifier()
    else
      # No default - Commanded requires explicit identifier configuration
      # For test fixtures that don't use Trogon.Commanded.Aggregate, return nil
      nil
    end
  end
end
