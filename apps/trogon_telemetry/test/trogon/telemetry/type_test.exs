defmodule Trogon.Telemetry.TypeTest do
  use ExUnit.Case, async: true

  alias Trogon.Telemetry.TestSupport.ProjectId
  alias Trogon.Telemetry.Type

  describe "valid?/1" do
    test "accepts the built-in shorthands" do
      assert Type.valid?(:integer)
      assert Type.valid?({:enum, [:ok, :error]})
      assert Type.valid?({:array, :string})
    end

    test "accepts a module without loading it" do
      assert Type.valid?(MyApp.NotCompiledYet)
    end

    test "rejects an atom that is not a module or a shorthand" do
      refute Type.valid?(:strng)
      refute Type.valid?({:enum, []})
      refute Type.valid?({:array, :strng})
    end
  end

  describe "dump/2" do
    test "leaves scalars alone" do
      assert Type.dump(:integer, 1) == 1
      assert Type.dump({:enum, [:ok]}, :ok) == :ok
      assert Type.dump(:string, nil) == nil
    end

    test "flattens a value object through its own implementation" do
      assert Type.dump(ProjectId, %ProjectId{value: "prj_1"}) == "prj_1"
    end

    test "flattens every element of a list" do
      assert Type.dump({:array, ProjectId}, [%ProjectId{value: "prj_1"}]) == ["prj_1"]
    end
  end

  describe "numeric?/1" do
    test "only the types a reporter can aggregate" do
      assert Type.numeric?(:integer)
      assert Type.numeric?(:float)
      assert Type.numeric?(:number)
      refute Type.numeric?(:string)
    end
  end
end
