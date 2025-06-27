defmodule Trogon.Commanded.EntityTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "enforces the identifier to be present" do
      {:error, changeset} = TestSupport.MyEntityOne.new(%{name: "billy"})
      assert %{uuid: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end
  end

  test "allow custom type as the identity" do
    uuid =
      TestSupport.AccountNumber.new!(%{
        account_number: "123e4567-e89b-12d3-a456-426655440000",
        branch: "123e4567-e89b-12d3-a456-426655440000"
      })

    assert {:ok, _command} = TestSupport.BankAccountEntity.new(%{uuid: uuid, type: :DEPOSITORY})
  end

  test "allow custom type as the identity fails when invalid value is passed" do
    {:error, changeset} =
      TestSupport.BankAccountEntity.new(%{uuid: "123e4567-e89b-12d3-a456-426655440000", type: :DEPOSITORY})

    assert %{uuid: ["is invalid"]} = TestSupport.errors_on(changeset)
  end
end
