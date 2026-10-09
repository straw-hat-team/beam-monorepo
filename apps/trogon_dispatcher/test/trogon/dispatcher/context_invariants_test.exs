defmodule Trogon.Dispatcher.ContextInvariantsTest do
  use ExUnit.Case, async: true

  alias Trogon.Dispatcher.Context
  alias Trogon.Dispatcher.DispatchOptions
  alias Trogon.Dispatcher.InvalidContextError
  alias Trogon.Dispatcher.TestSupport, as: Support

  require Trogon.Dispatcher.Test, as: Test

  defmodule OverwriteField do
    @moduledoc false
    @behaviour Trogon.Dispatcher.Middleware

    @impl true
    def call(context, next, field: field, value: value) do
      context |> Map.put(field, value) |> next.()
    end
  end

  setup do
    %{context: Test.build_context(%Support.RegisterUser{email: "a@b.c"}, DispatchOptions.new!(assigns: %{trail: []}))}
  end

  for {field, value} <- [
        message: %Support.ArchiveUser{id: 1},
        kind: :query,
        dispatcher: Support.RootDispatcher,
        registered_by: Support.RootDispatcher
      ] do
    test "rejects a middleware that changes #{field}", %{context: context} do
      error =
        assert_raise InvalidContextError, fn ->
          Test.call_middleware(OverwriteField, context,
            options: [field: unquote(field), value: unquote(Macro.escape(value))]
          )
        end

      assert %InvalidContextError{module: OverwriteField, field: unquote(field), reason: :changed} = error
    end
  end

  test "rejects a middleware that makes assigns something other than a map", %{context: context} do
    assert_raise InvalidContextError, ~r/whose :assigns is not a map/, fn ->
      Test.call_middleware(OverwriteField, context, options: [field: :assigns, value: [trail: []]])
    end
  end

  test "rejects a middleware that puts a non-atom key in assigns", %{context: context} do
    error =
      assert_raise InvalidContextError, fn ->
        Test.call_middleware(OverwriteField, context, options: [field: :assigns, value: %{"trail" => []}])
      end

    assert %InvalidContextError{module: OverwriteField, field: :assigns, reason: :non_atom_key} = error
  end

  test "rejects a middleware that makes private something other than a map", %{context: context} do
    error =
      assert_raise InvalidContextError, fn ->
        Test.call_middleware(OverwriteField, context, options: [field: :private, value: nil])
      end

    assert %InvalidContextError{field: :private, reason: :not_a_map} = error
  end

  test "accepts a middleware that only touches the fields it may", %{context: context} do
    context =
      Test.call_middleware(OverwriteField, context, options: [field: :assigns, value: %{trail: [:seen]}])

    assert %Context{assigns: %{trail: [:seen]}, response: :ok} = context
  end
end
