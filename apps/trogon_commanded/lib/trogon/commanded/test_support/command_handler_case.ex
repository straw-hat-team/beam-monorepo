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

  def assert_events(initial_events, command, expected_events, aggregate_module, command_handler_module) do
    run_and_assert(initial_events, command, aggregate_module, command_handler_module, fn
      {_state, actual_events, aggregate_uuid} ->
        expected = transform_identities(expected_events, aggregate_uuid, aggregate_module)
        assert actual_events == List.wrap(expected)

      {:error, reason} ->
        flunk("Expected success but got error: #{inspect(reason)}")
    end)
  end

  def assert_state(initial_events, command, expected_state, aggregate_module, command_handler_module) do
    run_and_assert(initial_events, command, aggregate_module, command_handler_module, fn
      {state, _events, aggregate_uuid} ->
        expected = transform_identities(expected_state, aggregate_uuid, aggregate_module)
        assert state == expected

      {:error, reason} ->
        flunk("Expected success but got error: #{inspect(reason)}")
    end)
  end

  def assert_error(initial_events, command, expected_error, aggregate_module, command_handler_module) do
    run_and_assert(initial_events, command, aggregate_module, command_handler_module, fn
      {:error, reason} -> assert reason == expected_error
      other -> flunk("Expected error #{inspect(expected_error)}, but got: #{inspect(other)}")
    end)
  end

  # Common assertion runner that eliminates duplication
  defp run_and_assert(initial_events, command, aggregate_module, command_handler_module, assertion_fn) do
    result = run_aggregate_with_identity(initial_events, command, aggregate_module, command_handler_module)
    assertion_fn.(result)
  end

  # Common function that runs aggregate with proper identity handling for all assertion types
  defp run_aggregate_with_identity(
         initial_events,
         command,
         aggregate_module,
         command_handler_module
       ) do
    assert is_list(initial_events), "Initial events must be a list of events"
    aggregate_uuid = extract_aggregate_identity(command, aggregate_module)

    # Transform initial events to use the correct stream ID (if applicable)
    transformed_initial_events =
      if aggregate_uuid do
        transform_identities(initial_events, aggregate_uuid, aggregate_module)
      else
        initial_events
      end

    # Validate that all transformed events belong to this aggregate
    validate_initial_events_belong_to_aggregate(transformed_initial_events, aggregate_uuid, aggregate_module)

    # Run the aggregate with consistent stream IDs
    result = aggregate_run(aggregate_module, command_handler_module, transformed_initial_events, command)

    # Return the result along with the aggregate_uuid for use in assertions
    case result do
      {:ok, state, events} -> {state, List.wrap(events), aggregate_uuid}
      other -> other
    end
  end

  defp aggregate_run(aggregate_module, command_handler_module, initial_events, command) do
    evolver = &aggregate_module.apply/2

    decider =
      if command_handler_module == nil,
        do: &aggregate_module.execute/2,
        else: &command_handler_module.handle/2

    result =
      aggregate_module
      |> struct()
      |> evolve(initial_events, evolver)
      |> execute(command, evolver, decider)

    # Transform the result to use the real aggregate identity (if applicable)
    aggregate_uuid = extract_aggregate_identity(command, aggregate_module)

    if aggregate_uuid do
      # This aggregate has identity configuration - transform the results
      case result do
        {:ok, state, events} ->
          transformed_events = transform_identities(events, aggregate_uuid, aggregate_module)
          transformed_state = transform_identities(state, aggregate_uuid, aggregate_module)
          {:ok, transformed_state, transformed_events}

        other ->
          other
      end
    else
      # This is a simple test fixture without identity configuration - return as-is
      result
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
    command_module = command.__struct__

    # Get identity configuration - try command module first, then aggregate module
    {identifier, identity_prefix} = get_identity_config(command_module, aggregate_module)

    # Use Commanded's middleware to extract the UUID
    %Pipeline{command: command, identity: identifier, identity_prefix: identity_prefix}
    |> ExtractAggregateIdentity.before_dispatch()
    |> case do
      %Pipeline{assigns: %{aggregate_uuid: uuid}} -> uuid
      %Pipeline{} -> nil
    end
  end

  # Extract identity configuration with fallback logic
  defp get_identity_config(command_module, aggregate_module) do
    if has_identity_functions?(command_module) do
      {command_module.aggregate_identifier(), command_module.identity_prefix()}
    else
      {get_identifier(aggregate_module), get_identity_prefix(aggregate_module)}
    end
  end

  defp has_identity_functions?(module) do
    function_exported?(module, :aggregate_identifier, 0) and
      function_exported?(module, :identity_prefix, 0)
  end

  defp get_identity_prefix(aggregate_module) do
    if function_exported?(aggregate_module, :identity_prefix, 0) do
      aggregate_module.identity_prefix()
    else
      # No prefix
      nil
    end
  end

  # Unified identity transformation for both events and state
  defp transform_identities(data, aggregate_uuid, aggregate_module) do
    identifier = get_identifier(aggregate_module)

    case data do
      items when is_list(items) -> Enum.map(items, &transform_single_item(&1, identifier, aggregate_uuid))
      single_item -> transform_single_item(single_item, identifier, aggregate_uuid)
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

  # Transform a single item's identifier if needed
  defp transform_single_item(item, identifier, aggregate_uuid) do
    with true <- identifier != nil and Map.has_key?(item, identifier),
         current when is_binary(current) <- Map.get(item, identifier),
         true <- current != aggregate_uuid do
      Map.put(item, identifier, aggregate_uuid)
    else
      _ -> item
    end
  end

  # Safely converts an identifier to string, handling protocol errors
  defp safe_to_string(nil), do: nil

  defp safe_to_string(value) do
    try do
      to_string(value)
    rescue
      Protocol.UndefinedError ->
        # For complex structs (Protobuf, etc.), return the original value
        value
    end
  end

  defp validate_initial_events_belong_to_aggregate(initial_events, aggregate_uuid, aggregate_module) do
    # Only validate when both aggregate_uuid and identifier are available
    with true <- aggregate_uuid != nil,
         identifier when identifier != nil <- get_identifier(aggregate_module) do
      initial_events
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.each(&validate_event_belongs_to_aggregate(&1, identifier, aggregate_uuid))
    end
  end

  defp validate_event_belongs_to_aggregate({event, index}, identifier, aggregate_uuid) do
    event_identifier = Map.get(event, identifier)

    # Only validate string identifiers for strict equality
    if is_binary(event_identifier) and is_binary(aggregate_uuid) and
         safe_to_string(event_identifier) != aggregate_uuid do
      flunk("""
      Initial event at index #{index} does not belong to the aggregate under test.
      Expected: #{inspect(aggregate_uuid)}
      Got: #{inspect(event_identifier)}
      Event: #{inspect(event)}
      """)
    end
  end
end
