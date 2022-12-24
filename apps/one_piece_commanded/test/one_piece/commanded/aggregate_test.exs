defmodule OnePiece.Commanded.AggregateTest do
  use ExUnit.Case, async: true

  describe "apply/1" do
    test "fallbacks respects the order of defining the function" do
      assert %TestSupport.MyAggregateOne{uuid: "123", name: "Hello, World!"} =
               TestSupport.MyAggregateOne.apply(%TestSupport.MyAggregateOne{}, %TestSupport.MyEventOne{
                 uuid: "123",
                 name: "Hello, World!"
               })
    end

    test "fallbacks to a default implementation of returning the aggregate as is" do
      assert %TestSupport.MyAggregateOne{} =
               TestSupport.MyAggregateOne.apply(%TestSupport.MyAggregateOne{}, %TestSupport.MyEventTwo{})
    end
  end
end
