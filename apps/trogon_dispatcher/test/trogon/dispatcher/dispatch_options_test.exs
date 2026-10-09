defmodule Trogon.Dispatcher.DispatchOptionsTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.InvalidDispatchOptionsError

  describe "new/1" do
    test "defaults every field" do
      assert {:ok, options} = DispatchOptions.new()
      assert options.message_id == nil
      assert options.correlation_id == nil
      assert options.causation_id == nil
      assert options.actor == nil
      assert options.assigns == %{}
    end

    test "keeps the given fields" do
      assert {:ok, options} =
               DispatchOptions.new(
                 message_id: "msg-1",
                 correlation_id: "corr-1",
                 causation_id: "cause-1",
                 actor: :someone,
                 assigns: %{trail: []}
               )

      assert options.message_id == "msg-1"
      assert options.correlation_id == "corr-1"
      assert options.causation_id == "cause-1"
      assert options.actor == :someone
      assert options.assigns == %{trail: []}
    end

    test "rejects a repeated key" do
      assert {:error, %InvalidDispatchOptionsError{} = error} = DispatchOptions.new(actor: :first, actor: :second)
      assert error.field == :actor
      assert error.value == [:first, :second]
      assert error.validation == :duplicate_key
    end

    test "rejects an unknown key" do
      assert {:error, %InvalidDispatchOptionsError{field: :private, validation: :unknown_key}} =
               DispatchOptions.new(private: %{})
    end
  end

  describe "new!/1" do
    test "raises on an unknown key" do
      assert_raise InvalidDispatchOptionsError, ~r/unknown dispatch option :private/, fn ->
        DispatchOptions.new!(private: %{})
      end
    end

    test "raises on a repeated key" do
      assert_raise InvalidDispatchOptionsError, ~r/dispatch option :actor given more than once/, fn ->
        DispatchOptions.new!(actor: :first, actor: :second)
      end
    end
  end
end
