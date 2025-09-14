defmodule Trogon.Commanded.TestSupport.CommandHandlerCaseTest do
  use ExUnit.Case, async: true

  alias Trogon.Commanded.TestSupport.CommandHandlerCase

  alias TestSupport.CommandHandlerCaseFixtures.{
    TestEvent,
    TestEventTwo,
    TestCommand,
    TestAggregate,
    TestCommandHandler,
    SingleEventAggregate
  }

  describe "assert_events/4" do
    test "passes when events match exactly" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :create_event},
        [%TestEvent{id: "test", name: "created"}],
        TestAggregate,
        nil
      )
    end

    test "passes with multiple events" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :create_multiple_events},
        [
          %TestEvent{id: "test", name: "first"},
          %TestEventTwo{id: "test", value: 42}
        ],
        TestAggregate,
        nil
      )
    end

    test "passes with initial events that modify aggregate state" do
      CommandHandlerCase.assert_events(
        [%TestEvent{id: "initial", name: "setup"}],
        %TestCommand{id: "test", action: :create_event},
        [%TestEvent{id: "test", name: "created"}],
        TestAggregate,
        nil
      )
    end

    test "passes with no events expected" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :no_events},
        [],
        TestAggregate,
        nil
      )
    end

    test "passes with {:ok, events} response" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :ok_tuple},
        [%TestEvent{id: "ok-tuple", name: "from_ok_tuple"}],
        TestAggregate,
        nil
      )
    end

    test "passes with {:ok, multiple_events} response" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :ok_tuple_multiple},
        [%TestEvent{id: "ok-multiple", name: "first"}, %TestEventTwo{id: "ok-multiple", value: 100}],
        TestAggregate,
        nil
      )
    end

    test "passes with nil response (no events)" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :nil_response},
        [],
        TestAggregate,
        nil
      )
    end

    test "passes with :ok response (no events)" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :ok_response},
        [],
        TestAggregate,
        nil
      )
    end

    test "passes with Multi response" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :multi},
        [%TestEvent{id: "multi", name: "multi_event"}],
        TestAggregate,
        nil
      )
    end

    test "passes with command handler" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :handler_create_event},
        [%TestEvent{id: "test", name: "from_handler"}],
        TestAggregate,
        TestCommandHandler
      )
    end

    test "fails when events don't match" do
      assert_raise ExUnit.AssertionError, fn ->
        CommandHandlerCase.assert_events(
          [],
          %TestCommand{id: "test", action: :create_event},
          [%TestEvent{id: "wrong", name: "wrong"}],
          TestAggregate,
          nil
        )
      end
    end

    test "fails when error is returned" do
      assert_raise ExUnit.AssertionError, fn ->
        CommandHandlerCase.assert_events(
          [],
          %TestCommand{id: "test", action: :error},
          [%TestEvent{id: "test", name: "created"}],
          TestAggregate,
          nil
        )
      end
    end
  end

  describe "assert_state/4" do
    test "passes when state matches exactly" do
      CommandHandlerCase.assert_state(
        [],
        %TestCommand{id: "test", action: :create_event},
        %TestAggregate{id: "test", name: "created", value: nil, processed_commands: nil},
        TestAggregate,
        nil
      )
    end

    test "passes with initial events that modify state" do
      CommandHandlerCase.assert_state(
        [%TestEvent{id: "initial", name: "setup"}],
        %TestCommand{id: "test", action: :create_event},
        %TestAggregate{id: "test", name: "created", value: nil, processed_commands: nil},
        TestAggregate,
        nil
      )
    end

    test "passes with Multi response that returns events" do
      CommandHandlerCase.assert_state(
        [],
        %TestCommand{id: "test", action: :multi},
        %TestAggregate{id: "multi", name: "multi_event", value: nil, processed_commands: nil},
        TestAggregate,
        nil
      )
    end

    test "passes with command handler" do
      CommandHandlerCase.assert_state(
        [],
        %TestCommand{id: "test", action: :handler_create_event},
        %TestAggregate{id: "test", name: "from_handler", value: nil, processed_commands: nil},
        TestAggregate,
        TestCommandHandler
      )
    end

    test "fails when state doesn't match" do
      assert_raise ExUnit.AssertionError, fn ->
        CommandHandlerCase.assert_state(
          [],
          %TestCommand{id: "test", action: :create_event},
          %TestAggregate{id: "wrong", name: "wrong", value: nil, processed_commands: nil},
          TestAggregate,
          nil
        )
      end
    end

    test "fails when error is returned" do
      assert_raise ExUnit.AssertionError, fn ->
        CommandHandlerCase.assert_state(
          [],
          %TestCommand{id: "test", action: :error},
          %TestAggregate{},
          TestAggregate,
          nil
        )
      end
    end
  end

  describe "assert_error/4" do
    test "passes when error matches exactly" do
      CommandHandlerCase.assert_error(
        [],
        %TestCommand{id: "test", action: :error},
        :something_went_wrong,
        TestAggregate,
        nil
      )
    end

    test "passes with Multi error" do
      CommandHandlerCase.assert_error(
        [],
        %TestCommand{id: "test", action: :multi_error},
        :multi_failed,
        TestAggregate,
        nil
      )
    end

    test "passes with command handler error" do
      CommandHandlerCase.assert_error(
        [],
        %TestCommand{id: "test", action: :handler_error},
        :handler_error,
        TestAggregate,
        TestCommandHandler
      )
    end

    test "fails when error doesn't match" do
      assert_raise ExUnit.AssertionError, fn ->
        CommandHandlerCase.assert_error(
          [],
          %TestCommand{id: "test", action: :error},
          :wrong_error,
          TestAggregate,
          nil
        )
      end
    end

    test "fails when success is returned instead of error" do
      assert_raise ExUnit.AssertionError, fn ->
        CommandHandlerCase.assert_error(
          [],
          %TestCommand{id: "test", action: :create_event},
          :some_error,
          TestAggregate,
          nil
        )
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles invalid response from execute function" do
      assert_raise ExUnit.AssertionError, ~r/unexpected:/, fn ->
        CommandHandlerCase.assert_events(
          [],
          %TestCommand{id: "test", action: :invalid_response},
          [],
          TestAggregate,
          nil
        )
      end
    end

    test "handles single event response (not in list)" do
      CommandHandlerCase.assert_events(
        [],
        %TestCommand{id: "test", action: :any},
        [%TestEvent{id: "single", name: "single_event"}],
        SingleEventAggregate,
        nil
      )
    end
  end

  describe "macro compilation failure tests" do
    test "raises error when neither aggregate nor handler provided" do
      assert_raise RuntimeError, ~r/you must provide at least `aggregate` or `handler`/, fn ->
        Code.compile_string("""
        defmodule InvalidConfigTest do
          use Trogon.Commanded.TestSupport.CommandHandlerCase
        end
        """)
      end
    end
  end
end
