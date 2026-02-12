defmodule Trogon.Commanded.CommandTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "enforces the aggregate identifier to be present" do
      {:error, changeset} = TestSupport.MyCommandOne.new(%{})
      assert %{uuid: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end
  end

  test "allow custom type as the identity" do
    uuid =
      TestSupport.AccountNumber.new!(%{
        account_number: "123e4567-e89b-12d3-a456-426655440000",
        branch: "123e4567-e89b-12d3-a456-426655440000"
      })

    assert {:ok, _command} = TestSupport.OpenDepositAccountCommand.new(%{uuid: uuid, type: :DEPOSITORY})
  end

  test "allow custom type as the identity fails when invalid value is passed" do
    {:error, changeset} = TestSupport.OpenDepositAccountCommand.new(%{uuid: "123e4567-e89b-12d3-a456-426655440000"})
    assert %{uuid: ["is invalid"]} = TestSupport.errors_on(changeset)
  end

  describe "proto-driven identity_prefix" do
    test "resolves prefix with default separator" do
      assert TestSupport.ProtoStreamCommand.identity_prefix() == "bank-account:"
    end

    test "resolves prefix with custom separator" do
      assert TestSupport.ProtoStreamOrderCommand.identity_prefix() == "order#"
    end
  end
end
