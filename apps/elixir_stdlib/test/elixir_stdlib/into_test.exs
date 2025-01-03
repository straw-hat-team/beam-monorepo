defmodule ElixirStdlib.IntoTest do
  alias TestSupport.MyCommand
  alias TestSupport.MyEvent

  use ExUnit.Case, async: true

  test "into" do
    assert ElixirStdlib.Into.into(%MyCommand{name: "test", value: 1}, MyEvent) == %MyEvent{
             name: "test",
             value: 1
           }
  end

  test "into a unknown type" do
    assert_raise FunctionClauseError, fn ->
      ElixirStdlib.Into.into(%MyCommand{name: "test", value: 1}, UnknownType)
    end
  end
end
