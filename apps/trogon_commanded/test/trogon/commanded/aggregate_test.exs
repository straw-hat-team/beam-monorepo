defmodule Trogon.Commanded.AggregateTest do
  use ExUnit.Case, async: true

  describe "apply/1" do
    test "fallbacks respects the order of defining the function" do
      assert %Trogon.Commanded.TestSupport.MyAggregateOne{uuid: "123", name: "Hello, World!"} =
               Trogon.Commanded.TestSupport.MyAggregateOne.apply(
                 %Trogon.Commanded.TestSupport.MyAggregateOne{},
                 %Trogon.Commanded.TestSupport.MyEventOne{
                   uuid: "123",
                   name: "Hello, World!"
                 }
               )
    end

    test "fallbacks to a default implementation of returning the aggregate as is" do
      assert %Trogon.Commanded.TestSupport.MyAggregateOne{} =
               Trogon.Commanded.TestSupport.MyAggregateOne.apply(
                 %Trogon.Commanded.TestSupport.MyAggregateOne{},
                 %Trogon.Commanded.TestSupport.MyEventTwo{}
               )
    end
  end

  describe "proto-driven identity_prefix" do
    test "resolves prefix with default separator" do
      assert Trogon.Commanded.TestSupport.ProtoStreamAggregate.identity_prefix() == "bank-account:"
    end

    test "resolves prefix with custom separator" do
      assert Trogon.Commanded.TestSupport.ProtoStreamOrderAggregate.identity_prefix() == "order#"
    end
  end
end
