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
      {:ok, _state, events} ->
        assert List.wrap(events) == List.wrap(expected_events)

      {:error, reason} ->
        flunk("Expected success but got error: #{inspect(reason)}")
    end)
  end

  def assert_state(initial_events, command, expected_state, aggregate_module, command_handler_module) do
    run_and_assert(initial_events, command, aggregate_module, command_handler_module, fn
      {:ok, state, _events} ->
        assert state == expected_state

      {:error, reason} ->
        flunk("Expected success but got error: #{inspect(reason)}")
    end)
  end

  def assert_error(initial_events, command, expected_error, aggregate_module, command_handler_module) do
    run_and_assert(initial_events, command, aggregate_module, command_handler_module, fn
      {:error, reason} -> assert reason == expected_error
      {:ok, _state, _events} -> flunk("Expected error #{inspect(expected_error)}, but command succeeded")
    end)
  end

  defp run_and_assert(initial_events, command, aggregate_module, command_handler_module, assertion_fn) do
    assert is_list(initial_events), "Initial events must be a list of events"
    validate_identity_configuration(command, aggregate_module)
    result = aggregate_run(aggregate_module, command_handler_module, initial_events, command)
    assertion_fn.(result)
  end

  defp aggregate_run(aggregate_module, command_handler_module, initial_events, command) do
    evolver = &aggregate_module.apply/2

    decider =
      if command_handler_module == nil,
        do: &aggregate_module.execute/2,
        else: &command_handler_module.handle/2

    aggregate_module
    |> struct()
    |> evolve(initial_events, evolver)
    |> execute(command, evolver, decider)
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

  defp validate_identity_configuration(command, aggregate_module) do
    command_module = command.__struct__

    command_has_identity? =
      function_exported?(command_module, :aggregate_identifier, 0) and
        function_exported?(command_module, :identity_prefix, 0)

    aggregate_has_identity? =
      function_exported?(aggregate_module, :identifier, 0) and
        function_exported?(aggregate_module, :identity_prefix, 0)

    if command_has_identity? and aggregate_has_identity? do
      validate_identifier_match(command_module, aggregate_module)
      validate_prefix_match(command_module, aggregate_module)
      validate_aggregate_uuid_extraction(command, command_module)
    else
      :ok
    end
  end

  defp validate_identifier_match(command_module, aggregate_module) do
    command_identifier = command_module.aggregate_identifier()
    aggregate_identifier = aggregate_module.identifier()

    assert command_identifier == aggregate_identifier, """
    Identity field mismatch between command and aggregate.

    Command #{inspect(command_module)} uses #{inspect(command_identifier)}
    Aggregate #{inspect(aggregate_module)} uses #{inspect(aggregate_identifier)}
    """
  end

  defp validate_prefix_match(command_module, aggregate_module) do
    command_prefix = command_module.identity_prefix()
    aggregate_prefix = aggregate_module.identity_prefix()

    assert command_prefix == aggregate_prefix, """
    Identity prefix mismatch between command and aggregate.

    Command #{inspect(command_module)} uses #{inspect(command_prefix)}
    Aggregate #{inspect(aggregate_module)} uses #{inspect(aggregate_prefix)}
    """
  end

  defp validate_aggregate_uuid_extraction(command, command_module) do
    identifier = command_module.aggregate_identifier()
    identity_prefix = command_module.identity_prefix()

    pipeline =
      %Pipeline{command: command, identity: identifier, identity_prefix: identity_prefix}
      |> ExtractAggregateIdentity.before_dispatch()

    case pipeline do
      %Pipeline{assigns: %{aggregate_uuid: uuid}} when is_binary(uuid) and uuid != "" ->
        :ok

      _ ->
        flunk("""
        Failed to extract aggregate UUID from command.

        Command: #{inspect(command)}
        Identity field: #{inspect(identifier)}
        Identity prefix: #{inspect(identity_prefix)}
        """)
    end
  end
end
