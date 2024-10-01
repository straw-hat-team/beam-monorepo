defmodule OnePiece.Commanded.EnumTest do
  use ExUnit.Case, async: true

  alias TestSupport.CommandRouterExample.BankAccountType

  test "values/0" do
    assert BankAccountType.values() == [:business, :personal]
  end

  test "specific enum values" do
    assert BankAccountType.business() == :business
    assert BankAccountType.personal() == :personal
  end

  test "cast/1" do
    assert BankAccountType.cast(:business) == {:ok, :business}
    assert BankAccountType.cast(:personal) == {:ok, :personal}
    assert BankAccountType.cast(:invalid) == :error

    assert BankAccountType.cast("business") == {:ok, :business}
    assert BankAccountType.cast("personal") == {:ok, :personal}
    assert BankAccountType.cast("invalid") == :error
  end

  test "loads/1" do
    assert BankAccountType.load("business") == {:ok, :business}
    assert BankAccountType.load("personal") == {:ok, :personal}
    assert BankAccountType.load("invalid") == :error
  end

  test "dump/1" do
    assert BankAccountType.dump(:business) == {:ok, "business"}
    assert BankAccountType.dump(:personal) == {:ok, "personal"}
    assert BankAccountType.dump(:invalid) == :error
  end
end
