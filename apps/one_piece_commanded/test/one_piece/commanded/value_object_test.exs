defmodule OnePiece.Commanded.ValueObjectTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "creates a struct" do
      assert {:ok, %TestSupport.MessageOne{title: nil}} = TestSupport.MessageOne.new(%{})
    end

    test "validates a key enforce" do
      {:error, changeset} = TestSupport.MessageTwo.new(%{})
      assert %{title: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end

    test "validates a key enforce for embed fields" do
      {:error, changeset} = TestSupport.MessageThree.new(%{})
      assert %{target: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end

    test "validates casting embed fields" do
      assert {:ok, %TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}} =
               TestSupport.MessageThree.new(%{target: %{title: "Hello, World!"}})
    end

    test "bypass casting structs" do
      assert {:ok, %TestSupport.MessageThree{target: %TestSupport.MessageOne{title: "Hello, World!"}}} =
               TestSupport.MessageThree.new(%{target: %TestSupport.MessageOne{title: "Hello, World!"}})
    end

    test "validates casting embed fields with a wrong value" do
      {:error, changeset} = TestSupport.MessageThree.new(%{target: "a wrong value"})
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
end
