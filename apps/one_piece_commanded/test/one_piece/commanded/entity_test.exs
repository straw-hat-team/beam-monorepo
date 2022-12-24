defmodule OnePiece.Commanded.EntityTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "enforces the identifier to be present" do
      {:error, changeset} = TestSupport.MyEntityOne.new(%{name: "billy"})
      assert %{uuid: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end
  end
end
