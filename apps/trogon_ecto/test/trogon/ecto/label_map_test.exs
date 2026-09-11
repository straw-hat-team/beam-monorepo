defmodule Trogon.Ecto.LabelMapTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.LabelMap
  alias Trogon.Ecto.TestSupport.WithKubernetesMetadata

  doctest LabelMap

  @params LabelMap.init([])

  describe "init/1" do
    test "fixes both rules to the Kubernetes label rules" do
      assert @params == %{
               key_format: :qualified_name,
               value_format: :label_value,
               max_key_length: :infinity,
               max_value_length: :infinity,
               validation: :label_map
             }
    end

    test "keeps the given bounds" do
      assert LabelMap.init(max_key_length: 32, max_value_length: 8).max_value_length == 8
    end

    test "refuses to have its rules overridden" do
      for opts <- [[key_format: :any], [value_format: :any], [key_format: :qualified_name]] do
        assert_raise ArgumentError, ~r/its rules are fixed/, fn -> LabelMap.init(opts) end
      end
    end

    test "rejects an unknown option" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:max_length\]/, fn ->
        LabelMap.init(max_length: 8)
      end
    end
  end

  describe "type/1" do
    test "is :map" do
      assert LabelMap.type(@params) == :map
    end
  end

  describe "cast/2" do
    test "accepts a selectable entry" do
      value = %{"tier" => "gold", "app.kubernetes.io/name" => "redis", "region" => ""}

      assert LabelMap.cast(value, @params) == {:ok, value}
    end

    test "rejects a value a label cannot hold" do
      for value <- ["gold tier", String.duplicate("a", 64), "example.com/gold"] do
        assert LabelMap.cast(%{"tier" => value}, @params) ==
                 {:error,
                  [
                    message: "has an invalid value for key: %{key}",
                    key: "tier",
                    validation: :label_map
                  ]}
      end
    end

    test "accepts uppercase in a name and in a value, since only the prefix is a DNS subdomain" do
      value = %{"Tier" => "Gold", "example.com/Tier" => "Gold"}

      assert LabelMap.cast(value, @params) == {:ok, value}
    end

    test "rejects an uppercase prefix, unlike an annotation key" do
      assert {:error, [{:message, "has an invalid key: %{key}"} | _rest]} =
               LabelMap.cast(%{"Example.com/tier" => "gold"}, @params)
    end

    test "passes nil through" do
      assert LabelMap.cast(nil, @params) == {:ok, nil}
    end

    test "honours a key bound narrower than the label rule" do
      params = LabelMap.init(max_key_length: 8)

      assert {:error, [{:message, "has a key longer than %{max_length} bytes"} | _rest]} =
               LabelMap.cast(%{"example.com/tier" => "gold"}, params)
    end

    test "honours a bound narrower than the label rule" do
      params = LabelMap.init(max_value_length: 3)

      assert {:error, [{:message, "has a value longer than %{max_length} bytes for key: %{key}"} | _rest]} =
               LabelMap.cast(%{"tier" => "gold"}, params)
    end
  end

  describe "load/3" do
    test "is lenient, so a row written before this type still reads" do
      assert LabelMap.load(%{"tier gold" => "gold"}, nil, @params) == {:ok, %{"tier gold" => "gold"}}
    end
  end

  describe "dump/3" do
    test "holds a value to the same rules as cast/2" do
      assert LabelMap.dump(%{"tier" => "gold"}, nil, @params) == {:ok, %{"tier" => "gold"}}
      assert LabelMap.dump(%{"tier" => "gold tier"}, nil, @params) == :error
    end
  end

  describe "embed_as/2" do
    test "is :dump, so a nested field is validated on write" do
      assert LabelMap.embed_as(:json, @params) == :dump
    end
  end

  describe "schema field declarations" do
    test "a field needs no options to enforce the label rules" do
      assert {:ok, %WithKubernetesMetadata{labels: %{"tier" => "gold"}}} =
               WithKubernetesMetadata.new(%{labels: %{"tier" => "gold"}})

      assert {:error, _changeset} = WithKubernetesMetadata.new(%{labels: %{"tier" => "gold tier"}})
    end

    test "a violation names the label map as its reason" do
      assert {:error, changeset} = WithKubernetesMetadata.new(%{labels: %{"-tier" => "gold"}})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "labels",
                 reason: :label_map,
                 message: "has an invalid key: -tier",
                 template: "has an invalid key: %{key}",
                 metadata: [key: "-tier"]
               }
             ]
    end
  end
end
