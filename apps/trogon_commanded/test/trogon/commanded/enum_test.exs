defmodule Trogon.Commanded.EnumTest do
  use ExUnit.Case, async: true

  alias TestSupport.CommandRouterExample.BankAccountType

  describe "new/1" do
    test "returns a value object" do
      assert {:ok, value} = BankAccountType.new(:business)
      assert value == %BankAccountType{value: :business}
    end

    test "returns a value object when passing a map" do
      assert {:ok, value} = BankAccountType.new(%{value: :business})
      assert value == %BankAccountType{value: :business}
    end

    test "returns an error when a validation fails" do
      assert {:error, changeset} = BankAccountType.new(nil)
      assert %{value: ["can't be blank"]} = TestSupport.errors_on(changeset)
    end

    test "with an invalid value" do
      assert {:error, changeset} = BankAccountType.new(:invalid)
      assert %{value: ["is invalid"]} = TestSupport.errors_on(changeset)
    end
  end

  describe "new!/1" do
    test "creates a value object" do
      assert %BankAccountType{value: :business} = BankAccountType.new!(:business)
    end

    test "creates a value object when passing a map" do
      assert %BankAccountType{value: :business} = BankAccountType.new!(%{value: :business})
    end

    test "raises an error when a validation fails" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        BankAccountType.new!(nil)
      end
    end

    test "raises an error with an invalid value" do
      assert_raise Ecto.InvalidChangesetError, fn ->
        BankAccountType.new!(:invalid)
      end
    end
  end

  test "values/0" do
    assert BankAccountType.values() == [:business, :personal]
  end

  test "specific enum values" do
    assert BankAccountType.business() == %BankAccountType{value: :business}
    assert BankAccountType.personal() == %BankAccountType{value: :personal}
  end

  describe "type/1" do
    test "returns the type of the enum" do
      assert BankAccountType.type() == :string
    end
  end

  describe "cast/1" do
    test "casts a map" do
      assert BankAccountType.cast(%{value: :business}) == {:ok, %BankAccountType{value: :business}}
    end

    test "casts atom values" do
      assert BankAccountType.cast(:business) == {:ok, %BankAccountType{value: :business}}
      assert BankAccountType.cast(:personal) == {:ok, %BankAccountType{value: :personal}}
      assert BankAccountType.cast(:invalid) == :error
    end

    test "casts string values" do
      assert BankAccountType.cast("business") == {:ok, %BankAccountType{value: :business}}
      assert BankAccountType.cast("personal") == {:ok, %BankAccountType{value: :personal}}
      assert BankAccountType.cast("invalid") == :error
    end

    test "casts existing struct" do
      existing = %BankAccountType{value: :business}
      assert BankAccountType.cast(existing) == {:ok, existing}
    end
  end

  describe "load/1" do
    test "loads string values" do
      assert BankAccountType.load("business") == {:ok, %BankAccountType{value: :business}}
      assert BankAccountType.load("personal") == {:ok, %BankAccountType{value: :personal}}
      assert BankAccountType.load("invalid") == :error
    end

    test "returns error for non-string values" do
      assert BankAccountType.load(:business) == :error
      assert BankAccountType.load(123) == :error
      assert BankAccountType.load(%{}) == :error
    end
  end

  describe "dump/1" do
    test "dumps struct to string" do
      assert BankAccountType.dump(%BankAccountType{value: :business}) == {:ok, "business"}
      assert BankAccountType.dump(%BankAccountType{value: :personal}) == {:ok, "personal"}
    end

    test "returns error for invalid values" do
      assert BankAccountType.dump(%BankAccountType{value: :invalid}) == :error
      assert BankAccountType.dump("business") == :error
      assert BankAccountType.dump(:business) == :error
      assert BankAccountType.dump(%{}) == :error
    end
  end

  describe "equal?/2" do
    test "returns true for matching values" do
      assert BankAccountType.equal?(%BankAccountType{value: :business}, %BankAccountType{value: :business})
      assert BankAccountType.equal?(%BankAccountType{value: :personal}, %BankAccountType{value: :personal})
    end

    test "returns false for different values" do
      refute BankAccountType.equal?(%BankAccountType{value: :business}, %BankAccountType{value: :personal})
    end

    test "returns false for non-struct values" do
      refute BankAccountType.equal?(%BankAccountType{value: :business}, :business)
      refute BankAccountType.equal?(:business, %BankAccountType{value: :business})
      refute BankAccountType.equal?("business", "business")
    end
  end

  describe "Jason.Encoder" do
    test "encodes to the value" do
      assert Jason.encode!(%BankAccountType{value: :business}) == ~s("business")
    end
  end

  test "works with embedded schemas" do
    expected_value = %TestSupport.CommandRouterExample.BankAccountOpened{
      uuid: "123",
      type: %TestSupport.CommandRouterExample.BankAccountOpened.BankAccountType{value: :business}
    }

    given_value =
      TestSupport.CommandRouterExample.BankAccountOpened.new!(%{
        uuid: "123",
        type: TestSupport.CommandRouterExample.BankAccountType.new!(:business)
      })

    assert expected_value == given_value
  end
end
