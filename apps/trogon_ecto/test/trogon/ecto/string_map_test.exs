defmodule Trogon.Ecto.StringMapTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.StringMap
  alias Trogon.Ecto.TestSupport
  alias Trogon.Ecto.TestSupport.WithConfiguredStringMap
  alias Trogon.Ecto.TestSupport.WithStringMap

  doctest StringMap

  @any_params StringMap.init([])
  @strict_params StringMap.init(key_format: :qualified_name, value_format: :label_value)

  describe "init/1" do
    test "leaves every rule unconstrained by default" do
      assert StringMap.init([]) == %{
               key_format: :any,
               value_format: :any,
               max_key_length: :infinity,
               max_value_length: :infinity,
               validation: :string_map
             }
    end

    test "keeps the given formats" do
      assert StringMap.init(key_format: :qualified_name, value_format: :label_value) ==
               %{
                 key_format: :qualified_name,
                 value_format: :label_value,
                 max_key_length: :infinity,
                 max_value_length: :infinity,
                 validation: :string_map
               }
    end

    test "keeps the case-insensitive key format" do
      assert StringMap.init(key_format: :qualified_name_ignoring_case) ==
               %{
                 key_format: :qualified_name_ignoring_case,
                 value_format: :any,
                 max_key_length: :infinity,
                 max_value_length: :infinity,
                 validation: :string_map
               }
    end

    test "keeps the given bounds" do
      assert StringMap.init(max_key_length: 32, max_value_length: 4_096) ==
               %{
                 key_format: :any,
                 value_format: :any,
                 max_key_length: 32,
                 max_value_length: 4_096,
                 validation: :string_map
               }
    end

    test "accepts the options Ecto passes through from field/3" do
      assert StringMap.init(field: :labels, schema: WithStringMap, default: %{}) ==
               %{
                 key_format: :any,
                 value_format: :any,
                 max_key_length: :infinity,
                 max_value_length: :infinity,
                 validation: :string_map
               }
    end

    test "rejects an unknown option" do
      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:key_formats\]/, fn ->
        StringMap.init(key_formats: :qualified_name)
      end
    end

    test "rejects an unknown format" do
      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :key_format/, fn ->
        StringMap.init(key_format: :dns_label)
      end

      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :value_format/, fn ->
        StringMap.init(value_format: :annotation_value)
      end
    end

    test "rejects a bound that is not a positive length" do
      for bound <- [0, -1, "32", :none] do
        assert_raise NimbleOptions.ValidationError, ~r/invalid value for :max_key_length/, fn ->
          StringMap.init(max_key_length: bound)
        end

        assert_raise NimbleOptions.ValidationError, ~r/invalid value for :max_value_length/, fn ->
          StringMap.init(max_value_length: bound)
        end
      end
    end
  end

  describe "type/1" do
    test "is :map" do
      assert StringMap.type(@any_params) == :map
    end
  end

  describe "cast/2" do
    test "keeps a map of strings as it was given" do
      assert StringMap.cast(%{"tier" => "gold", "region" => "eu"}, @any_params) ==
               {:ok, %{"tier" => "gold", "region" => "eu"}}
    end

    test "passes an empty map through" do
      assert StringMap.cast(%{}, @any_params) == {:ok, %{}}
    end

    test "keeps an empty value, which Kubernetes allows" do
      assert StringMap.cast(%{"app.kubernetes.io/part-of" => ""}, @strict_params) ==
               {:ok, %{"app.kubernetes.io/part-of" => ""}}
    end

    test "passes nil through, since an absent map is not an empty one" do
      assert StringMap.cast(nil, @any_params) == {:ok, nil}
    end

    test "rejects a value that is not a map" do
      for value <- ["tier=gold", 123, :gold, [], [{"a", "b"}], true] do
        assert StringMap.cast(value, @any_params) == :error
      end
    end

    test "rejects a struct, which would otherwise be read as its fields" do
      for value <- [~U[2024-01-01 00:00:00Z], ~D[2024-01-01], %URI{}] do
        assert StringMap.cast(value, @any_params) == :error
      end
    end

    test "rejects a key that is not a string rather than converting it" do
      for key <- [:tier, 1, nil, %{"a" => "b"}, ["a"], {:a, :b}] do
        assert StringMap.cast(%{key => "gold"}, @any_params) ==
                 {:error, [message: "has a key that is not a string", validation: :string_map]}
      end
    end

    test "rejects a value that is not a string rather than converting it" do
      for value <- [:gold, 3, 1.5, true, false, %{"team" => "core"}, ["a"], {:a, :b}] do
        assert StringMap.cast(%{"owner" => value}, @any_params) ==
                 {:error,
                  [
                    message: "has a value that is not a string",
                    key: "owner",
                    validation: :string_map
                  ]}
      end
    end

    test "rejects a nil value rather than keeping it or emptying it" do
      assert StringMap.cast(%{"owner" => nil}, @any_params) ==
               {:error,
                [
                  message: "has a value that is not a string",
                  key: "owner",
                  validation: :string_map
                ]}
    end
  end

  describe "cast/2 with key_format: :qualified_name" do
    test "accepts a bare name" do
      for key <- ["tier", "a", "app.kubernetes.io", "some_key", "some-key", "A1"] do
        assert StringMap.cast(%{key => "gold"}, @strict_params) == {:ok, %{key => "gold"}}
      end
    end

    test "accepts a prefixed name" do
      for key <- ["app.kubernetes.io/name", "example.com/tier", "a/b"] do
        assert StringMap.cast(%{key => "gold"}, @strict_params) == {:ok, %{key => "gold"}}
      end
    end

    test "accepts a name of 63 bytes and a prefix of 253" do
      key = "#{String.duplicate("a", 253)}/#{String.duplicate("b", 63)}"

      assert StringMap.cast(%{key => "gold"}, @strict_params) == {:ok, %{key => "gold"}}
    end

    test "rejects a name longer than 63 bytes" do
      key = String.duplicate("a", 64)

      assert StringMap.cast(%{key => "gold"}, @strict_params) ==
               {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
    end

    test "rejects a prefix longer than 253 bytes" do
      key = "#{String.duplicate("a", 254)}/name"

      assert StringMap.cast(%{key => "gold"}, @strict_params) ==
               {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
    end

    test "rejects a key that does not begin and end alphanumeric" do
      for key <- ["-tier", "tier-", ".tier", "tier.", "_tier", "tier_"] do
        assert StringMap.cast(%{key => "gold"}, @strict_params) ==
                 {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
      end
    end

    test "rejects a key holding a character outside the rule" do
      for key <- ["tier gold", "tier!", "tier:gold", "tiér"] do
        assert StringMap.cast(%{key => "gold"}, @strict_params) ==
                 {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
      end
    end

    test "rejects an empty key, with or without a prefix" do
      for key <- ["", "/name", "example.com/"] do
        assert StringMap.cast(%{key => "gold"}, @strict_params) ==
                 {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
      end
    end

    test "rejects a trailing newline anywhere in the key" do
      for key <- ["tier\n", "example.com/tier\n", "example.com\n/tier"] do
        assert StringMap.cast(%{key => "gold"}, @strict_params) ==
                 {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
      end
    end

    test "rejects a second slash" do
      key = "example.com/a/b"

      assert StringMap.cast(%{key => "gold"}, @strict_params) ==
               {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
    end

    test "rejects an uppercase prefix, which is not a DNS subdomain" do
      key = "Example.com/tier"

      assert StringMap.cast(%{key => "gold"}, @strict_params) ==
               {:error, [message: "has an invalid key: %{key}", key: key, validation: :string_map]}
    end

    test "accepts an uppercase prefix under key_format: :qualified_name_ignoring_case" do
      params = StringMap.init(key_format: :qualified_name_ignoring_case)

      for key <- ["Example.com/tier", "EXAMPLE.COM/Tier", "example.com/tier"] do
        assert StringMap.cast(%{key => "gold"}, params) == {:ok, %{key => "gold"}}
      end
    end

    test "still rejects a malformed key under key_format: :qualified_name_ignoring_case" do
      params = StringMap.init(key_format: :qualified_name_ignoring_case)

      for key <- ["-tier", "example.com/a/b", "tier gold", "Tier\n", ""] do
        assert {:error, _error} = StringMap.cast(%{key => "gold"}, params)
      end
    end

    test "leaves the key alone under key_format: :any" do
      for key <- ["tier gold", "-tier", "example.com/a/b", ""] do
        assert StringMap.cast(%{key => "gold"}, @any_params) == {:ok, %{key => "gold"}}
      end
    end
  end

  describe "cast/2 with value_format: :label_value" do
    test "accepts an empty value" do
      assert StringMap.cast(%{"tier" => ""}, @strict_params) == {:ok, %{"tier" => ""}}
    end

    test "accepts a value of 63 bytes" do
      value = String.duplicate("a", 63)

      assert StringMap.cast(%{"tier" => value}, @strict_params) == {:ok, %{"tier" => value}}
    end

    test "accepts a value holding every character the rule allows" do
      for value <- ["Gold", "gold_tier", "gold.tier", "gold-tier", "v1.2.3-rc_4", "A1"] do
        assert StringMap.cast(%{"tier" => value}, @strict_params) == {:ok, %{"tier" => value}}
      end
    end

    test "rejects a value longer than 63 bytes" do
      value = String.duplicate("a", 64)

      assert StringMap.cast(%{"tier" => value}, @strict_params) ==
               {:error,
                [
                  message: "has an invalid value for key: %{key}",
                  key: "tier",
                  validation: :string_map
                ]}
    end

    test "rejects a value with a trailing newline" do
      assert StringMap.cast(%{"tier" => "gold\n"}, @strict_params) ==
               {:error,
                [
                  message: "has an invalid value for key: %{key}",
                  key: "tier",
                  validation: :string_map
                ]}
    end

    test "rejects a value holding a character outside the rule" do
      for value <- ["gold tier", "gold!", "example.com/gold", "-gold"] do
        assert StringMap.cast(%{"tier" => value}, @strict_params) ==
                 {:error,
                  [
                    message: "has an invalid value for key: %{key}",
                    key: "tier",
                    validation: :string_map
                  ]}
      end
    end

    test "leaves the value alone under value_format: :any, as an annotation does" do
      params = StringMap.init(key_format: :qualified_name)
      value = String.duplicate("a", 500)

      assert StringMap.cast(%{"example.com/note" => value}, params) ==
               {:ok, %{"example.com/note" => value}}
    end
  end

  describe "cast/2 with length bounds" do
    test "accepts a key and a value at the bound" do
      params = StringMap.init(max_key_length: 4, max_value_length: 4)

      assert StringMap.cast(%{"tier" => "gold"}, params) == {:ok, %{"tier" => "gold"}}
    end

    test "rejects a key over the bound, keeping it out of the message" do
      params = StringMap.init(max_key_length: 3)

      assert StringMap.cast(%{"tier" => "gold"}, params) ==
               {:error,
                [
                  message: "has a key longer than %{max_length} bytes",
                  max_length: 3,
                  key: "tier",
                  validation: :string_map
                ]}
    end

    test "rejects a value over the bound" do
      params = StringMap.init(max_value_length: 3)

      assert StringMap.cast(%{"tier" => "gold"}, params) ==
               {:error,
                [
                  message: "has a value longer than %{max_length} bytes for key: %{key}",
                  max_length: 3,
                  key: "tier",
                  validation: :string_map
                ]}
    end

    test "counts bytes rather than characters" do
      params = StringMap.init(max_value_length: 3)

      assert StringMap.cast(%{"tier" => "ä"}, params) == {:ok, %{"tier" => "ä"}}

      assert {:error, _error} = StringMap.cast(%{"tier" => "ääa"}, params)
    end

    test "bounds the whole key rather than either part of a qualified name" do
      params = StringMap.init(key_format: :qualified_name, max_key_length: 16)

      assert StringMap.cast(%{"example.com/tier" => "gold"}, params) ==
               {:ok, %{"example.com/tier" => "gold"}}

      assert {:error, [{:message, "has a key longer than %{max_length} bytes"} | _rest]} =
               StringMap.cast(%{"example.com/region" => "gold"}, params)
    end

    test "reports the bound before the format, the narrower rule of the two" do
      params = StringMap.init(value_format: :label_value, max_value_length: 3)

      assert {:error, [{:message, "has a value longer than %{max_length} bytes for key: %{key}"} | _rest]} =
               StringMap.cast(%{"tier" => "gold"}, params)
    end

    test "leaves length alone when unbound" do
      value = String.duplicate("a", 100_000)

      assert StringMap.cast(%{value => value}, @any_params) == {:ok, %{value => value}}
    end
  end

  describe "load/3" do
    test "loads a map of strings as it was stored" do
      assert StringMap.load(%{"tier" => "gold"}, nil, @any_params) == {:ok, %{"tier" => "gold"}}
    end

    test "loads a row written before this type was in place" do
      assert StringMap.load(%{"tier" => 1, "owner" => nil}, nil, @any_params) ==
               {:ok, %{"tier" => 1, "owner" => nil}}
    end

    test "loads a row written before a format was tightened" do
      assert StringMap.load(%{"tier gold" => "gold"}, nil, @strict_params) ==
               {:ok, %{"tier gold" => "gold"}}
    end

    test "loads a map whose keys are not strings" do
      stored = %{1 => "one", tier: "gold"}

      assert StringMap.load(stored, nil, @strict_params) == {:ok, stored}
    end

    test "loads nil as nil" do
      assert StringMap.load(nil, nil, @any_params) == {:ok, nil}
    end

    test "rejects a value that is not a map" do
      for value <- ["tier=gold", 123, [], ~U[2024-01-01 00:00:00Z]] do
        assert StringMap.load(value, nil, @any_params) == :error
      end
    end
  end

  describe "dump/3" do
    test "dumps a map of strings as it was given" do
      assert StringMap.dump(%{"tier" => "gold"}, nil, @any_params) == {:ok, %{"tier" => "gold"}}
    end

    test "dumps an empty map" do
      assert StringMap.dump(%{}, nil, @any_params) == {:ok, %{}}
    end

    test "dumps nil as nil" do
      assert StringMap.dump(nil, nil, @any_params) == {:ok, nil}
    end

    test "refuses to convert on the way out" do
      for value <- [%{tier: "gold"}, %{"tier" => 1}, %{"tier" => nil}] do
        assert StringMap.dump(value, nil, @any_params) == :error
      end
    end

    test "holds a value to the same format as cast/2" do
      assert StringMap.dump(%{"tier gold" => "gold"}, nil, @strict_params) == :error
      assert StringMap.dump(%{"tier" => "gold tier"}, nil, @strict_params) == :error
    end

    test "refuses to write back a legacy row that load/3 accepted" do
      legacy = %{"tier" => 1}

      assert StringMap.load(legacy, nil, @any_params) == {:ok, legacy}
      assert StringMap.dump(legacy, nil, @any_params) == :error
    end

    test "rejects a value that is not a map" do
      for value <- ["tier=gold", 123, [], ~U[2024-01-01 00:00:00Z]] do
        assert StringMap.dump(value, nil, @any_params) == :error
      end
    end
  end

  describe "round trip" do
    test "a cast value round-trips exactly" do
      for value <- [%{"tier" => "gold", "replicas" => "2"}, %{"a" => ""}, %{}] do
        assert {:ok, cast} = StringMap.cast(value, @strict_params)
        assert {:ok, dumped} = StringMap.dump(cast, nil, @strict_params)
        assert {:ok, ^cast} = StringMap.load(dumped, nil, @strict_params)
      end
    end
  end

  describe "schema field declarations" do
    test "a field takes a map of strings" do
      assert {:ok, %WithStringMap{labels: %{"tier" => "gold"}}} =
               WithStringMap.new(%{labels: %{"tier" => "gold"}})
    end

    test "an absent field stays nil" do
      assert {:ok, %WithStringMap{labels: nil}} = WithStringMap.new(%{})
    end

    test "a field reports why it was rejected" do
      assert {:error, changeset} = WithStringMap.new(%{labels: %{"owner" => %{"team" => "core"}}})

      assert TestSupport.errors_on(changeset) == %{
               labels: ["has a value that is not a string"]
             }
    end

    test "a field carries its own format" do
      attrs = %{labels: %{"tier" => "gold tier"}, annotations: %{"tier" => "gold tier"}}

      assert {:error, changeset} = WithConfiguredStringMap.new(attrs)

      assert TestSupport.errors_on(changeset) == %{
               labels: ["has an invalid value for key: tier"]
             }
    end

    test "an annotation takes a value a label would not" do
      attrs = %{annotations: %{"example.com/note" => "a longer sentence, with punctuation."}}

      assert {:ok, %WithConfiguredStringMap{}} = WithConfiguredStringMap.new(attrs)
    end

    test "the rejection reports as its own violation reason" do
      assert {:error, changeset} = WithStringMap.new(%{labels: %{"owner" => nil}})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "labels",
                 reason: :string_map,
                 message: "has a value that is not a string",
                 template: "has a value that is not a string",
                 metadata: [key: "owner"]
               }
             ]
    end

    test "a field given something that is not a map reports as a cast failure" do
      assert {:error, changeset} = WithStringMap.new(%{labels: "tier=gold"})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "labels",
                 reason: :cast,
                 message: "is invalid",
                 template: "is invalid",
                 metadata: []
               }
             ]
    end

    test "a field with several bad entries reports one violation, not one per entry" do
      attrs = %{labels: %{"tier gold" => "gold", "-owner" => "core", "region" => "us east"}}

      assert {:error, changeset} = WithConfiguredStringMap.new(attrs)
      assert [%Trogon.Ecto.FieldViolation{field: "labels"}] = Trogon.Ecto.Changeset.field_violations(changeset)
    end

    test "a bound reports the limit it went over" do
      value = String.duplicate("a", 65)

      assert {:error, changeset} = WithConfiguredStringMap.new(%{annotations: %{"example.com/note" => value}})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "annotations",
                 reason: :string_map,
                 message: "has a value longer than 64 bytes for key: example.com/note",
                 template: "has a value longer than %{max_length} bytes for key: %{key}",
                 metadata: [max_length: 64, key: "example.com/note"]
               }
             ]
    end

    test "the offending key stays out of the template and in the metadata" do
      assert {:error, changeset} = WithConfiguredStringMap.new(%{labels: %{"-tier" => "gold"}})

      assert Trogon.Ecto.Changeset.field_violations(changeset) == [
               %Trogon.Ecto.FieldViolation{
                 field: "labels",
                 reason: :string_map,
                 message: "has an invalid key: -tier",
                 template: "has an invalid key: %{key}",
                 metadata: [key: "-tier"]
               }
             ]
    end
  end

  describe "embed_as/2" do
    test "is :dump for every format" do
      for format <- [:json, :self] do
        assert StringMap.embed_as(format, @any_params) == :dump
      end
    end

    test "a nested annotation map is dumped as a plain map" do
      value_object = struct!(WithStringMap, labels: %{"region" => "us_east"})

      assert {:ok, %{labels: %{"region" => "us_east"}}} = WithStringMap.dump(value_object)
    end

    test "the dumped value object is JSON encodable" do
      value_object = struct!(WithStringMap, labels: %{"region" => "us_east"})
      {:ok, dumped} = WithStringMap.dump(value_object)

      assert {:ok, ~s({"labels":{"region":"us_east"}})} = Jason.encode(dumped)
    end

    test "a nil value survives the round trip" do
      value_object = struct!(WithStringMap, labels: nil)

      assert {:ok, %{labels: nil}} = WithStringMap.dump(value_object)
    end

    test "a map built with struct!/2 that is not all strings cannot be dumped" do
      value_object = struct!(WithStringMap, labels: %{"replicas" => 3})

      assert_raise ArgumentError, ~r/cannot dump `%{"replicas" => 3}`/, fn ->
        WithStringMap.dump(value_object)
      end
    end

    test "a map built with struct!/2 that breaks the format cannot be dumped either" do
      value_object = struct!(WithConfiguredStringMap, labels: %{"-tier" => "gold"})

      assert_raise ArgumentError, ~r/cannot dump/, fn ->
        WithConfiguredStringMap.dump(value_object)
      end
    end
  end
end
