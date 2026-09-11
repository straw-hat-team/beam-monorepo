defmodule Trogon.Ecto.ErrorMessageTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.ErrorMessage

  describe "interpolate/1" do
    test "returns a message with no placeholders unchanged" do
      assert ErrorMessage.interpolate({"can't be blank", []}) == "can't be blank"
    end

    test "replaces a placeholder with its binding" do
      assert ErrorMessage.interpolate({"should be at most %{count} character(s)", [count: 5]}) ==
               "should be at most 5 character(s)"
    end

    test "replaces every placeholder in the message" do
      assert ErrorMessage.interpolate({"%{count} of %{kind}", [count: 2, kind: :list]}) ==
               "2 of list"
    end

    test "replaces every occurrence of the same placeholder" do
      assert ErrorMessage.interpolate({"%{val} and %{val}", [val: "x"]}) == "x and x"
    end

    test "leaves a placeholder with no binding alone" do
      assert ErrorMessage.interpolate({"got %{value}", []}) == "got %{value}"
    end

    test "leaves a placeholder alone when a different key is bound" do
      assert ErrorMessage.interpolate({"got %{value}", [count: 5]}) == "got %{value}"
    end

    test "keeps a string binding as it is" do
      assert ErrorMessage.interpolate({"got %{value}", [value: "hello"]}) == "got hello"
    end

    test "writes a number binding the way it is written in Elixir" do
      assert ErrorMessage.interpolate({"got %{value}", [value: 5]}) == "got 5"
      assert ErrorMessage.interpolate({"got %{value}", [value: -1]}) == "got -1"
      assert ErrorMessage.interpolate({"got %{value}", [value: 1.5]}) == "got 1.5"
    end

    test "writes an atom binding without its colon" do
      assert ErrorMessage.interpolate({"got %{value}", [value: :max]}) == "got max"
    end

    test "inspects a binding that has no string form" do
      for {value, expected} <- [
            {[1, 2], "got [1, 2]"},
            {{:a, :b}, "got {:a, :b}"},
            {%{a: 1}, "got %{a: 1}"},
            {nil, "got nil"},
            {["a", "b"], ~s(got ["a", "b"])}
          ] do
        assert ErrorMessage.interpolate({"got %{value}", [value: value]}) == expected
      end
    end

    test "inspects a struct binding rather than raising" do
      assert ErrorMessage.interpolate({"got %{value}", [value: ~D[2024-01-01]]}) ==
               "got ~D[2024-01-01]"
    end

    test "renders the metadata Ecto attaches to a parameterized cast error" do
      type = {:parameterized, {Trogon.Ecto.BoundedString, %{max_length: 5, truncate: false}}}

      assert ErrorMessage.interpolate({"is invalid", [type: type, validation: :cast]}) ==
               "is invalid"
    end
  end
end
