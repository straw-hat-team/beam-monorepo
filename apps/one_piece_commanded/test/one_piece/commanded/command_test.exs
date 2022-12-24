defmodule OnePiece.Commanded.CommandTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "enforces the aggregate identifier to be present" do
      {:error, changeset} = TestSupport.MyCommandOne.new(%{})
      assert %{uuid: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end
  end
end
