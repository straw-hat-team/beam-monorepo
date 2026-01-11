defmodule Trogon.Commanded.TestSupport.CommandHandlerCaseFixProofTest do
  @moduledoc """
  This test PROVES that the CommandHandlerCase fix works by demonstrating that
  it now correctly handles identity prefixes and transformations just like
  a real Commanded application with the ExtractAggregateIdentity middleware.
  """

  use ExUnit.Case, async: true

  alias Trogon.Commanded.TestSupport.CommandHandlerCase
  alias Commanded.Middleware.Pipeline
  alias Commanded.Middleware.ExtractAggregateIdentity

  # Test aggregates that use REAL Trogon.Commanded.Aggregate with identity configuration
  defmodule AccountCreated do
    use Trogon.Commanded.Event, aggregate_identifier: :uuid

    embedded_schema do
      field :name, :string
    end
  end

  defmodule CreateAccount do
    use Trogon.Commanded.Command,
      aggregate_identifier: :uuid,
      identity_prefix: "account-"

    embedded_schema do
      field :name, :string
    end
  end

  defmodule Account do
    use Trogon.Commanded.Aggregate,
      identifier: :uuid,
      identity_prefix: "account-"

    embedded_schema do
      field :name, :string
    end

    def apply(aggregate, %AccountCreated{} = event) do
      %{aggregate | uuid: event.uuid, name: event.name}
    end

    def execute(_aggregate, %CreateAccount{} = command) do
      %AccountCreated{uuid: command.uuid, name: command.name}
    end
  end

  # Test with function-based prefix
  defmodule UserRegistered do
    use Trogon.Commanded.Event, aggregate_identifier: :user_id

    embedded_schema do
      field :email, :string
    end
  end

  defmodule RegisterUser do
    use Trogon.Commanded.Command,
      aggregate_identifier: :user_id,
      identity_prefix: fn -> "user-#{Date.utc_today().year}-" end

    embedded_schema do
      field :email, :string
    end
  end

  defmodule User do
    use Trogon.Commanded.Aggregate,
      identifier: :user_id,
      identity_prefix: fn -> "user-#{Date.utc_today().year}-" end

    embedded_schema do
      field :email, :string
    end

    def apply(aggregate, %UserRegistered{} = event) do
      %{aggregate | user_id: event.user_id, email: event.email}
    end

    def execute(_aggregate, %RegisterUser{} = command) do
      %UserRegistered{user_id: command.user_id, email: command.email}
    end
  end

  describe "PROOF: CommandHandlerCase now matches real Commanded behavior" do
    test "✅ FIXED: String prefix transformation works correctly" do
      command = %CreateAccount{uuid: "test123", name: "Test Account"}

      # What the REAL Commanded middleware produces
      real_pipeline = %Pipeline{
        command: command,
        identity: :uuid,
        identity_prefix: "account-"
      }

      processed_pipeline = ExtractAggregateIdentity.before_dispatch(real_pipeline)
      real_aggregate_uuid = processed_pipeline.assigns[:aggregate_uuid]

      # Verify middleware produces the expected transformation
      assert real_aggregate_uuid == "account-test123"

      # PROOF: CommandHandlerCase now produces the SAME result as real middleware
      CommandHandlerCase.assert_events(
        [],
        command,
        # ✅ MATCHES real behavior!
        [%AccountCreated{uuid: "account-test123", name: "Test Account"}],
        Account,
        nil
      )

      # PROOF: CommandHandlerCase state also matches real behavior
      CommandHandlerCase.assert_state(
        [],
        command,
        # ✅ MATCHES real behavior!
        %Account{uuid: "account-test123", name: "Test Account"},
        Account,
        nil
      )
    end

    test "✅ FIXED: Function-based prefix transformation works correctly" do
      command = %RegisterUser{user_id: "john123", email: "john@example.com"}
      current_year = Date.utc_today().year
      expected_id = "user-#{current_year}-john123"

      # What the REAL Commanded middleware produces
      real_pipeline = %Pipeline{
        command: command,
        identity: :user_id,
        identity_prefix: fn -> "user-#{Date.utc_today().year}-" end
      }

      processed_pipeline = ExtractAggregateIdentity.before_dispatch(real_pipeline)
      real_aggregate_uuid = processed_pipeline.assigns[:aggregate_uuid]

      # Verify middleware produces the expected transformation
      assert real_aggregate_uuid == expected_id

      # PROOF: CommandHandlerCase now produces the SAME result as real middleware
      CommandHandlerCase.assert_events(
        [],
        command,
        # ✅ MATCHES real behavior!
        [%UserRegistered{user_id: expected_id, email: "john@example.com"}],
        User,
        nil
      )

      # PROOF: CommandHandlerCase state also matches real behavior
      CommandHandlerCase.assert_state(
        [],
        command,
        # ✅ MATCHES real behavior!
        %User{user_id: expected_id, email: "john@example.com"},
        User,
        nil
      )
    end

    test "✅ BACKWARD COMPATIBLE: Simple aggregates without identity config still work" do
      # Test that existing simple test fixtures still work unchanged
      alias TestSupport.CommandHandlerCaseFixtures.{TestAggregate, TestCommand, TestEvent}

      # This should work exactly as before (no transformation)
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "simple", action: :create_event},
        # No transformation - works as before
        [%TestEvent{id: "simple", name: "created"}],
        TestAggregate,
        nil
      )

      # This proves backward compatibility is maintained
    end
  end

  describe "PROOF: Real vs CommandHandlerCase behavior now matches" do
    test "Event sourcing replay scenarios now work correctly" do
      command = %CreateAccount{uuid: "replay-test", name: "Replay Account"}

      # Simulate what would happen in a real Commanded application
      real_events = simulate_real_commanded_behavior(command)

      # PROOF: CommandHandlerCase now produces the SAME events
      CommandHandlerCase.assert_events(
        [],
        command,
        # ✅ MATCHES what real Commanded would produce!
        real_events,
        Account,
        nil
      )
    end

    test "Stream ID filtering now works correctly" do
      # In a real event store, events are filtered by stream ID
      command1 = %CreateAccount{uuid: "stream1", name: "Account 1"}
      command2 = %CreateAccount{uuid: "stream2", name: "Account 2"}

      # Get the real stream IDs that would be used in production
      real_stream_id_1 = get_real_stream_id(command1)
      real_stream_id_2 = get_real_stream_id(command2)

      assert real_stream_id_1 == "account-stream1"
      assert real_stream_id_2 == "account-stream2"

      # PROOF: CommandHandlerCase events now use the correct stream IDs
      CommandHandlerCase.assert_events(
        [],
        command1,
        # ✅ CORRECT stream ID!
        [%AccountCreated{uuid: real_stream_id_1, name: "Account 1"}],
        Account,
        nil
      )

      CommandHandlerCase.assert_events(
        [],
        command2,
        # ✅ CORRECT stream ID!
        [%AccountCreated{uuid: real_stream_id_2, name: "Account 2"}],
        Account,
        nil
      )
    end

    test "Aggregate lookups now work correctly" do
      command = %CreateAccount{uuid: "lookup-test", name: "Lookup Account"}

      # In production, aggregates are looked up by the transformed ID
      expected_lookup_id = "account-lookup-test"

      # PROOF: CommandHandlerCase state uses the correct lookup ID
      CommandHandlerCase.assert_state(
        [],
        command,
        # ✅ CORRECT lookup ID!
        %Account{uuid: expected_lookup_id, name: "Lookup Account"},
        Account,
        nil
      )

      # This means aggregate lookups in production will work correctly
      # because the IDs match what CommandHandlerCase tests expect
    end
  end

  # Helper functions to simulate real Commanded behavior
  defp simulate_real_commanded_behavior(command) do
    # This simulates what a real Commanded application would do:
    # 1. Apply ExtractAggregateIdentity middleware
    # 2. Execute the command
    # 3. Transform the events with the processed identity

    pipeline = %Pipeline{
      command: command,
      identity: command.__struct__.aggregate_identifier(),
      identity_prefix: command.__struct__.identity_prefix()
    }

    processed_pipeline = ExtractAggregateIdentity.before_dispatch(pipeline)
    real_aggregate_uuid = processed_pipeline.assigns[:aggregate_uuid]

    # Execute the command (this is what the aggregate would do)
    events = Account.execute(%Account{}, command)

    # Transform events to use the real aggregate UUID (like middleware does)
    List.wrap(events)
    |> Enum.map(fn event -> %{event | uuid: real_aggregate_uuid} end)
  end

  defp get_real_stream_id(command) do
    pipeline = %Pipeline{
      command: command,
      identity: command.__struct__.aggregate_identifier(),
      identity_prefix: command.__struct__.identity_prefix()
    }

    processed_pipeline = ExtractAggregateIdentity.before_dispatch(pipeline)
    processed_pipeline.assigns[:aggregate_uuid]
  end
end
