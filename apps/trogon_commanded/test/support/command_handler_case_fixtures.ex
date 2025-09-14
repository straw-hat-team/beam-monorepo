defmodule TestSupport.CommandHandlerCaseFixtures do
  alias Commanded.Aggregate.Multi

  defmodule TestEvent do
    defstruct [:id, :name]
  end

  defmodule TestEventTwo do
    defstruct [:id, :value]
  end

  defmodule TestCommand do
    defstruct [:id, :action]
  end

  defmodule TestAggregate do
    defstruct [:id, :name, :value, :processed_commands]

    def apply(aggregate, %TestEvent{} = event) do
      %{aggregate | id: event.id, name: event.name}
    end

    def apply(aggregate, %TestEventTwo{} = event) do
      %{aggregate | id: event.id, value: event.value}
    end

    def execute(_aggregate, %TestCommand{action: :create_event} = command) do
      %TestEvent{id: command.id, name: "created"}
    end

    def execute(_aggregate, %TestCommand{action: :create_multiple_events} = command) do
      [
        %TestEvent{id: command.id, name: "first"},
        %TestEventTwo{id: command.id, value: 42}
      ]
    end

    def execute(_aggregate, %TestCommand{action: :no_events}) do
      []
    end

    def execute(_aggregate, %TestCommand{action: :ok_tuple}) do
      {:ok, %TestEvent{id: "ok-tuple", name: "from_ok_tuple"}}
    end

    def execute(_aggregate, %TestCommand{action: :ok_tuple_multiple}) do
      {:ok, [%TestEvent{id: "ok-multiple", name: "first"}, %TestEventTwo{id: "ok-multiple", value: 100}]}
    end

    def execute(_aggregate, %TestCommand{action: :nil_response}) do
      nil
    end

    def execute(_aggregate, %TestCommand{action: :ok_response}) do
      :ok
    end

    def execute(_aggregate, %TestCommand{action: :error}) do
      {:error, :something_went_wrong}
    end

    def execute(aggregate, %TestCommand{action: :multi}) do
      Multi.new(aggregate)
      |> Multi.execute(&execute_multi_step/1)
    end

    def execute(aggregate, %TestCommand{action: :multi_error}) do
      Multi.new(aggregate)
      |> Multi.execute(fn _aggregate -> {:error, :multi_failed} end)
    end

    def execute(_aggregate, %TestCommand{action: :invalid_response}) do
      "invalid response"
    end

    defp execute_multi_step(_aggregate) do
      [%TestEvent{id: "multi", name: "multi_event"}]
    end
  end

  defmodule TestCommandHandler do
    def handle(aggregate, command) do
      processed_commands = (aggregate.processed_commands || []) ++ [command]
      updated_aggregate = %{aggregate | processed_commands: processed_commands}

      case command do
        %TestCommand{action: :handler_create_event} = cmd ->
          %TestEvent{id: cmd.id, name: "from_handler"}

        %TestCommand{action: :handler_error} ->
          {:error, :handler_error}

        %TestCommand{action: :handler_multi} ->
          Multi.new(updated_aggregate)
          |> Multi.execute(fn _agg ->
            {updated_aggregate, [%TestEvent{id: "handler_multi", name: "from_handler_multi"}]}
          end)
      end
    end
  end

  defmodule TestCommandHandler.Aggregate do
    defstruct [:id, :processed_commands]

    def apply(aggregate, %TestEvent{} = event) do
      %{aggregate | id: event.id}
    end
  end

  defmodule SingleEventAggregate do
    defstruct [:id]

    def apply(aggregate, _event), do: aggregate

    def execute(_aggregate, _command) do
      %TestEvent{id: "single", name: "single_event"}
    end
  end
end
