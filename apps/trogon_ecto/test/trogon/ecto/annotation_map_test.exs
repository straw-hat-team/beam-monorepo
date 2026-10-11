defmodule Trogon.Ecto.AnnotationMapTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.AnnotationMap
  alias Trogon.Ecto.TestSupport.WithKubernetesMetadata

  doctest AnnotationMap

  @params AnnotationMap.init([])

  describe "init/1" do
    test "fixes the key rule and leaves values free" do
      assert @params == %{
               key_format: :qualified_name_ignoring_case,
               value_format: :any,
               max_key_length: :infinity,
               max_value_length: :infinity,
               validation: :annotation_map
             }
    end

    test "keeps the given bounds" do
      assert AnnotationMap.init(max_value_length: 4_096).max_value_length == 4_096
    end

    test "refuses to have its rules overridden" do
      for opts <- [[key_format: :any], [value_format: :label_value]] do
        assert_raise ArgumentError, ~r/its rules are fixed/, fn -> AnnotationMap.init(opts) end
      end
    end

    test "rejects an unknown option" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:max_length\]/, fn ->
        AnnotationMap.init(max_length: 8)
      end
    end
  end

  describe "type/1" do
    test "is :map" do
      assert AnnotationMap.type(@params) == :map
    end
  end

  describe "cast/2" do
    test "takes any value, which is the point of an annotation" do
      value = %{
        "example.com/note" => "a longer sentence, with punctuation.",
        "example.com/config" => ~s({"replicas":3}),
        "example.com/empty" => ""
      }

      assert AnnotationMap.cast(value, @params) == {:ok, value}
    end

    test "matches the key against its lowercased form, as Kubernetes does" do
      for key <- ["Example.com/tier", "EXAMPLE.COM/Tier"] do
        assert AnnotationMap.cast(%{key => "gold"}, @params) == {:ok, %{key => "gold"}}
      end
    end

    test "still rejects a key that is no qualified name" do
      for key <- ["-tier", "example.com/a/b", "tier gold", ""] do
        assert {:error, [{:message, "has an invalid key: %{key}"} | _rest]} =
                 AnnotationMap.cast(%{key => "gold"}, @params)
      end
    end

    test "rejects a value that is not a string" do
      assert AnnotationMap.cast(%{"example.com/tier" => nil}, @params) ==
               {:error,
                [
                  message: "has a value that is not a string",
                  key: "example.com/tier",
                  validation: :annotation_map
                ]}
    end

    test "passes nil through" do
      assert AnnotationMap.cast(nil, @params) == {:ok, nil}
    end

    test "bounds a key when asked to" do
      params = AnnotationMap.init(max_key_length: 8)

      assert {:error, [{:message, "has a key longer than %{max_length} bytes"} | _rest]} =
               AnnotationMap.cast(%{"example.com/note" => "a"}, params)
    end

    test "bounds a value when asked to" do
      params = AnnotationMap.init(max_value_length: 8)

      assert {:error, [{:message, "has a value longer than %{max_length} bytes for key: %{key}"} | _rest]} =
               AnnotationMap.cast(%{"example.com/note" => "a longer sentence"}, params)
    end
  end

  describe "load/3" do
    test "is lenient, so a row written before this type still reads" do
      assert AnnotationMap.load(%{"tier gold" => "gold"}, nil, @params) == {:ok, %{"tier gold" => "gold"}}
    end
  end

  describe "dump/3" do
    test "holds a value to the same rules as cast/2" do
      assert AnnotationMap.dump(%{"tier" => "anything at all"}, nil, @params) ==
               {:ok, %{"tier" => "anything at all"}}

      assert AnnotationMap.dump(%{"-tier" => "gold"}, nil, @params) == :error
    end
  end

  describe "embed_as/2" do
    test "is :dump, so a nested field is validated on write" do
      assert AnnotationMap.embed_as(:json, @params) == :dump
    end
  end

  describe "schema field declarations" do
    test "a field takes an annotation a label would reject" do
      attrs = %{annotations: %{"example.com/note" => "a longer sentence, with punctuation."}}

      assert {:ok, %WithKubernetesMetadata{}} = WithKubernetesMetadata.new(attrs)
    end

    test "a violation names the annotation map as its reason" do
      value = String.duplicate("a", 65)

      assert {:error, changeset} =
               WithKubernetesMetadata.new(%{annotations: %{"example.com/note" => value}})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "annotations",
                 reason: :annotation_map,
                 message: "has a value longer than 64 bytes for key: example.com/note",
                 template: "has a value longer than %{max_length} bytes for key: %{key}",
                 metadata: [max_length: 64, key: "example.com/note"]
               }
             ]
    end
  end
end
