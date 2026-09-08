defmodule Trogon.Commanded.TestSupport.CommandHandlerCaseIdentityTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.TestSupport.CommandHandlerCase

  alias TestSupport.CommandHandlerCaseFixtures.{
    TestAggregate,
    TestCommand,
    TestEvent
  }

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

  defmodule MismatchedPrefixCommand do
    use Trogon.Commanded.Command,
      aggregate_identifier: :uuid,
      identity_prefix: "wrong-prefix-"

    embedded_schema do
      field :name, :string
    end
  end

  defmodule MismatchedFieldCommand do
    use Trogon.Commanded.Command,
      aggregate_identifier: :account_id,
      identity_prefix: "account-"

    embedded_schema do
      field :name, :string
    end
  end

  describe "identity configuration validation" do
    test "passes when command and aggregate identity config match" do
      CommandHandlerCase.assert_events(
        [],
        %CreateAccount{uuid: "test123", name: "Test Account"},
        [%AccountCreated{uuid: "test123", name: "Test Account"}],
        Account,
        nil
      )
    end

    test "passes state assertion when config matches" do
      CommandHandlerCase.assert_state(
        [],
        %CreateAccount{uuid: "test123", name: "Test Account"},
        %Account{uuid: "test123", name: "Test Account"},
        Account,
        nil
      )
    end

    test "fails when identity prefix does not match" do
      assert_raise ExUnit.AssertionError, ~r/Identity prefix mismatch/, fn ->
        CommandHandlerCase.assert_events(
          [],
          %MismatchedPrefixCommand{uuid: "test123", name: "Test"},
          [],
          Account,
          nil
        )
      end
    end

    test "fails when identity field does not match" do
      assert_raise ExUnit.AssertionError, ~r/Identity field mismatch/, fn ->
        CommandHandlerCase.assert_events(
          [],
          %MismatchedFieldCommand{account_id: "test123", name: "Test"},
          [],
          Account,
          nil
        )
      end
    end

    test "fails when aggregate UUID cannot be extracted" do
      assert_raise ExUnit.AssertionError, ~r/Failed to extract aggregate UUID/, fn ->
        CommandHandlerCase.assert_events(
          [],
          %CreateAccount{uuid: nil, name: "Test"},
          [],
          Account,
          nil
        )
      end
    end

    test "validates identity on assert_error path" do
      assert_raise ExUnit.AssertionError, ~r/Identity prefix mismatch/, fn ->
        CommandHandlerCase.assert_error(
          [],
          %MismatchedPrefixCommand{uuid: "test123", name: "Test"},
          :some_error,
          Account,
          nil
        )
      end
    end

  end

  defmodule PlainAggregate do
    defstruct [:uuid, :name]

    def apply(aggregate, %AccountCreated{} = event) do
      %{aggregate | uuid: event.uuid, name: event.name}
    end

    def execute(_aggregate, %CreateAccount{} = command) do
      %AccountCreated{uuid: command.uuid, name: command.name}
    end
  end

  describe "skips validation when only one side has identity config" do
    test "trogon command with plain struct aggregate" do
      CommandHandlerCase.assert_events(
        [],
        %CreateAccount{uuid: "test123", name: "Test"},
        [%AccountCreated{uuid: "test123", name: "Test"}],
        PlainAggregate,
        nil
      )
    end
  end

  describe "backward compatibility" do
    test "neither side has identity config" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "simple", action: :create_event},
        [%TestEvent{id: "simple", name: "created"}],
        TestAggregate,
        nil
      )
    end
  end
end
