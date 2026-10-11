defmodule Trogon.Commanded.EntityTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "enforces the identifier to be present" do
      {:error, changeset} = Trogon.Commanded.TestSupport.MyEntityOne.new(%{name: "billy"})
      assert %{uuid: ["can't be blank"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
    end
  end

  test "allow custom type as the identity" do
    uuid =
      Trogon.Commanded.TestSupport.AccountNumber.new!(%{
        account_number: "123e4567-e89b-12d3-a456-426655440000",
        branch: "123e4567-e89b-12d3-a456-426655440000"
      })

    assert {:ok, _command} = Trogon.Commanded.TestSupport.BankAccountEntity.new(%{uuid: uuid, type: :DEPOSITORY})
  end

  test "allow custom type as the identity fails when invalid value is passed" do
    {:error, changeset} =
      Trogon.Commanded.TestSupport.BankAccountEntity.new(%{
        uuid: "123e4567-e89b-12d3-a456-426655440000",
        type: :DEPOSITORY
      })

    assert %{uuid: ["is invalid"]} = Trogon.Commanded.TestSupport.errors_on(changeset)
  end
end
