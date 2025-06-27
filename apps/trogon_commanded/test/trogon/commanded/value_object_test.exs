defmodule Trogon.Commanded.ValueObjectTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "overriding validate/2" do
      assert {:ok, %TestSupport.TransferableMoney{amount: 1, currency: :USD}} =
               TestSupport.TransferableMoney.new(%{amount: 1, currency: :USD})

      assert {:error, changeset} = TestSupport.TransferableMoney.new(%{amount: 0, currency: :USD})
      assert %{amount: ["must be greater than 0"]} = TestSupport.errors_on(changeset)
    end

    test "creates a struct" do
      assert {:ok, %TestSupport.MessageOne{title: nil}} = TestSupport.MessageOne.new(%{})
    end

    test "validates a key enforce" do
      assert {:error, changeset} = TestSupport.MessageTwo.new(%{})
      assert %{title: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end

    test "validates a key enforce for embed fields" do
      assert {:error, changeset} = TestSupport.MessageThree.new(%{})
      assert %{target: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end

    test "validates casting embed fields" do
      assert {:ok, %TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}} =
               TestSupport.MessageThree.new(%{target: %{title: "Hello, World!"}})
    end

    test "casting structs" do
      assert {:ok, %TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}} =
               TestSupport.MessageThree.new(%{target: %TestSupport.MessageOne{title: "Hello, World!"}})

      assert {:ok,
              %TestSupport.MessageFour{
                targets: [%TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}]
              }} =
               TestSupport.MessageFour.new(%{
                 targets: [
                   TestSupport.MessageThree.new!(%{target: TestSupport.MessageOne.new!(%{title: "Hello, World!"})})
                 ]
               })
    end

    test "validates casting embed fields with a wrong value" do
      assert {:error, changeset} = TestSupport.MessageThree.new(%{target: "a wrong value"})
      assert %{target: ["is invalid"]} = TestSupport.errors_on(changeset)
    end
  end

  describe "new!/1" do
    test "raises an error when a validation fails" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        TestSupport.MessageTwo.new!(%{})
      end
    end
  end

  describe "cast/1" do
    test "casts a struct" do
      assert {:ok, message} = TestSupport.MessageOne.cast(%TestSupport.MessageOne{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "casts a map" do
      assert {:ok, message} = TestSupport.MessageOne.cast(%{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "casts a map with a wrong value" do
      assert :error = TestSupport.MessageOne.cast(%{title: 1})
    end

    test "casts an invalid input" do
      assert :error = TestSupport.MessageOne.cast(1)
    end
  end

  describe "load/1" do
    test "loads a map" do
      assert {:ok, message} = TestSupport.MessageOne.load(%{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "loads a struct" do
      assert {:ok, message} = TestSupport.MessageOne.load(%{title: "Hello, World!"})
      assert message.title == "Hello, World!"
    end

    test "loads an invalid input" do
      assert :error = TestSupport.MessageOne.load(1)
    end
  end

  describe "dump/1" do
    test "dumps a struct" do
      assert {:ok, %{title: "Hello, World!"}} =
               TestSupport.MessageOne.dump(%TestSupport.MessageOne{title: "Hello, World!"})
    end

    test "dumps an invalid input" do
      assert :error = TestSupport.MessageOne.dump(1)
    end
  end

  describe "changeset/2" do
    test "validates the struct" do
      assert {:error, changeset} = TestSupport.MyValueOject.new(%{amount: 0})
      assert %{amount: ["must be greater than 0"]} = TestSupport.errors_on(changeset)
    end
  end
end
