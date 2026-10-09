defmodule Trogon.Dispatcher.DispatchOptionsTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.InvalidDispatchOptionsError
  alias Trogon.Dispatcher.TestSupport, as: Support

  describe "new/1" do
    test "defaults every field" do
      assert {:ok, options} = DispatchOptions.new()
      assert DispatchOptions.message_id(options) == nil
      assert DispatchOptions.correlation_id(options) == nil
      assert DispatchOptions.causation_id(options) == nil
      assert DispatchOptions.actor(options) == nil
      assert DispatchOptions.assigns(options) == %{}
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

      assert DispatchOptions.message_id(options) == "msg-1"
      assert DispatchOptions.correlation_id(options) == "corr-1"
      assert DispatchOptions.causation_id(options) == "cause-1"
      assert DispatchOptions.actor(options) == :someone
      assert DispatchOptions.assigns(options) == %{trail: []}
    end

    test "rejects options that are not a keyword list" do
      assert {:error, %InvalidDispatchOptionsError{reason: :not_a_keyword}} = DispatchOptions.new(%{actor: :someone})
    end

    test "rejects an unknown key" do
      assert {:error, %InvalidDispatchOptionsError{field: :private, reason: :unknown_key}} =
               DispatchOptions.new(private: %{})
    end

    test "rejects assigns that are not a map" do
      assert {:error, %InvalidDispatchOptionsError{field: :assigns, reason: :not_a_map}} =
               DispatchOptions.new(assigns: [trail: []])

      assert {:error, %InvalidDispatchOptionsError{field: :assigns, reason: :not_a_map}} =
               DispatchOptions.new(assigns: nil)
    end

    test "rejects assigns with a non-atom key" do
      assert {:error, %InvalidDispatchOptionsError{field: :assigns, reason: :non_atom_key}} =
               DispatchOptions.new(assigns: %{"trail" => []})
    end
  end

  describe "new!/1" do
    test "raises when an invariant does not hold" do
      assert_raise InvalidDispatchOptionsError, "expected dispatch option :assigns to be a map, got: nil", fn ->
        DispatchOptions.new!(assigns: nil)
      end
    end
  end

  describe "dispatching a struct literal that skipped new/1" do
    test "raises at the dispatcher boundary for a registered message" do
      assert_raise InvalidDispatchOptionsError, fn ->
        Support.AccountsDispatcher.dispatch_message(%Support.ArchiveUser{id: 1}, %DispatchOptions{assigns: nil})
      end
    end

    test "raises at the dispatcher boundary for an unregistered message" do
      assert_raise InvalidDispatchOptionsError, fn ->
        Support.AccountsDispatcher.dispatch_message(%Support.NotRegistered{}, %DispatchOptions{assigns: nil})
      end
    end
  end
end
