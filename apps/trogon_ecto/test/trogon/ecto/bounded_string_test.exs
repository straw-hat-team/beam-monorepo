defmodule Trogon.Ecto.BoundedStringTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.BoundedString
  alias Trogon.Ecto.TestSupport
  alias Trogon.Ecto.TestSupport.WithBoundedString
  alias Trogon.Ecto.TestSupport.WithTruncatedBoundedString

  doctest BoundedString

  describe "init/1" do
    test "raises when :max_length is missing" do
      assert_raise NimbleOptions.ValidationError, ~r/required :max_length option not found/, fn ->
        BoundedString.init([])
      end
    end

    test "raises for a non-positive :max_length" do
      for max_length <- [0, -1] do
        assert_raise NimbleOptions.ValidationError,
                     ~r/invalid value for :max_length option: expected positive integer/,
                     fn -> BoundedString.init(max_length: max_length) end
      end
    end

    test "raises for a non-integer :max_length" do
      for max_length <- ["80", 80.0, nil, :eighty] do
        assert_raise NimbleOptions.ValidationError,
                     ~r/invalid value for :max_length option: expected positive integer/,
                     fn -> BoundedString.init(max_length: max_length) end
      end
    end

    test "raises for a non-boolean :truncate" do
      assert_raise NimbleOptions.ValidationError,
                   ~r/invalid value for :truncate option: expected boolean/,
                   fn -> BoundedString.init(max_length: 80, truncate: :yes) end
    end

    test "defaults :truncate to false" do
      assert BoundedString.init(max_length: 80) == %{max_length: 80, truncate: false}
    end

    test "ignores the keys Ecto injects" do
      assert BoundedString.init(max_length: 80, field: :title, schema: WithBoundedString) ==
               %{max_length: 80, truncate: false}
    end

    test "ignores every option Ecto's field/3 documents" do
      ecto_field_opts = [
        default: "x",
        source: :the_title,
        autogenerate: false,
        read_after_writes: false,
        virtual: false,
        primary_key: false,
        load_in_query: true,
        redact: true,
        skip_default_validation: true,
        writable: :always,
        on_writable_violation: :raise
      ]

      assert Keyword.keys(ecto_field_opts) -- Trogon.Ecto.FieldOptions.keys() == []

      assert BoundedString.init([max_length: 80] ++ ecto_field_opts) ==
               %{max_length: 80, truncate: false}
    end

    test "raises for an unknown option" do
      for opts <- [[max_length: 80, bogus: 1], [max_length: 80, truncat: true], [max_lenght: 80]] do
        assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:[a-z_]+\]/, fn ->
          BoundedString.init(opts)
        end
      end
    end
  end

  describe "type/1" do
    test "is :string" do
      assert BoundedString.type(BoundedString.init(max_length: 80)) == :string
    end
  end

  describe "cast/2" do
    setup do
      %{params: BoundedString.init(max_length: 5)}
    end

    test "accepts a value within the bound", %{params: params} do
      assert BoundedString.cast("hello", params) == {:ok, "hello"}
    end

    test "accepts a value exactly at the bound", %{params: params} do
      assert BoundedString.cast("12345", params) == {:ok, "12345"}
    end

    test "accepts an empty string", %{params: params} do
      assert BoundedString.cast("", params) == {:ok, ""}
    end

    test "accepts nil", %{params: params} do
      assert BoundedString.cast(nil, params) == {:ok, nil}
    end

    test "rejects an oversized value with validate_length/3 error metadata", %{params: params} do
      assert BoundedString.cast("hello world", params) ==
               {:error,
                [
                  message: "should be at most %{count} character(s)",
                  count: 5,
                  validation: :length,
                  kind: :max,
                  type: :string
                ]}
    end

    test "rejects a value of an unsupported type", %{params: params} do
      for value <- [123, 1.5, :hello, [], %{}, true, ["hello"]] do
        assert BoundedString.cast(value, params) == :error
      end
    end

    test "counts graphemes rather than bytes" do
      params = BoundedString.init(max_length: 5)

      assert BoundedString.cast("héllo", params) == {:ok, "héllo"}
      assert byte_size("héllo") > 5
    end

    test "counts a combined grapheme as one character" do
      params = BoundedString.init(max_length: 1)

      assert BoundedString.cast("é", params) == {:ok, "é"}
    end
  end

  describe "cast/2 with truncate: true" do
    setup do
      %{params: BoundedString.init(max_length: 5, truncate: true)}
    end

    test "cuts an oversized value at the bound", %{params: params} do
      assert BoundedString.cast("hello world", params) == {:ok, "hello"}
    end

    test "leaves a value within the bound untouched", %{params: params} do
      assert BoundedString.cast("hey", params) == {:ok, "hey"}
    end

    test "never splits a grapheme" do
      params = BoundedString.init(max_length: 2, truncate: true)

      assert BoundedString.cast("héllo", params) == {:ok, "hé"}
    end

    test "passes nil through", %{params: params} do
      assert BoundedString.cast(nil, params) == {:ok, nil}
    end

    test "still rejects a value of an unsupported type", %{params: params} do
      assert BoundedString.cast(123, params) == :error
    end
  end

  describe "load/3" do
    setup do
      %{params: BoundedString.init(max_length: 5)}
    end

    test "loads a binary as-is", %{params: params} do
      assert BoundedString.load("hello", & &1, params) == {:ok, "hello"}
    end

    test "loads a value that predates the bound", %{params: params} do
      assert BoundedString.load("hello world", & &1, params) == {:ok, "hello world"}
    end

    test "loads nil as nil", %{params: params} do
      assert BoundedString.load(nil, & &1, params) == {:ok, nil}
    end

    test "rejects a non-binary value", %{params: params} do
      assert BoundedString.load(123, & &1, params) == :error
    end
  end

  describe "dump/3" do
    setup do
      %{params: BoundedString.init(max_length: 5)}
    end

    test "dumps a binary as-is", %{params: params} do
      assert BoundedString.dump("hello", & &1, params) == {:ok, "hello"}
    end

    test "dumps nil as nil", %{params: params} do
      assert BoundedString.dump(nil, & &1, params) == {:ok, nil}
    end

    test "rejects a non-binary value", %{params: params} do
      assert BoundedString.dump(123, & &1, params) == :error
    end

    test "rejects an oversized value that never went through cast/2", %{params: params} do
      assert BoundedString.dump("hello world", & &1, params) == :error
    end

    test "truncates an oversized value under `truncate: true`" do
      params = BoundedString.init(max_length: 5, truncate: true)

      assert BoundedString.dump("hello world", & &1, params) == {:ok, "hello"}
    end

    test "refuses to write back a legacy value that load/3 accepted", %{params: params} do
      legacy = "a value stored before the bound"

      assert BoundedString.load(legacy, & &1, params) == {:ok, legacy}
      assert BoundedString.dump(legacy, & &1, params) == :error
    end

    test "a legacy value is truncated on write back under `truncate: true`" do
      params = BoundedString.init(max_length: 5, truncate: true)
      legacy = "a value stored before the bound"

      assert BoundedString.load(legacy, & &1, params) == {:ok, legacy}
      assert BoundedString.dump(legacy, & &1, params) == {:ok, "a val"}
    end
  end

  describe "round trip" do
    test "a cast value round-trips exactly" do
      params = BoundedString.init(max_length: 5)

      for value <- ["hello", "héllo", "", "12345"] do
        assert {:ok, cast} = BoundedString.cast(value, params)
        assert {:ok, dumped} = BoundedString.dump(cast, & &1, params)
        assert {:ok, ^cast} = BoundedString.load(dumped, & &1, params)
      end
    end
  end

  describe "schema field declarations" do
    test "the bound is enforced without any changeset validation" do
      assert {:error, changeset} = WithBoundedString.new(%{title: "hello world"})

      assert TestSupport.errors_on(changeset) == %{title: ["should be at most 5 character(s)"]}
    end

    test "a value within the bound is accepted" do
      assert {:ok, %WithBoundedString{title: "hello"}} = WithBoundedString.new(%{title: "hello"})
    end

    test "`truncate: true` cuts the value the changeset ends up holding" do
      assert {:ok, %WithTruncatedBoundedString{title: "hello"}} =
               WithTruncatedBoundedString.new(%{title: "hello world"})
    end

    test "the changeset error keeps the length metadata but replaces `:type`" do
      assert {:error, %Ecto.Changeset{errors: [title: {_message, metadata}]}} =
               WithBoundedString.new(%{title: "hello world"})

      assert Keyword.take(metadata, [:count, :validation, :kind]) ==
               [count: 5, validation: :length, kind: :max]

      assert Keyword.fetch!(metadata, :type) ==
               {:parameterized, {BoundedString, %{max_length: 5, truncate: false}}}
    end
  end

  describe "embed_as/2" do
    test "is :dump for every format" do
      params = BoundedString.init(max_length: 5)

      for format <- [:json, :self] do
        assert BoundedString.embed_as(format, params) == :dump
      end
    end

    test "a nested bounded string is dumped as a plain string" do
      value_object = struct!(WithBoundedString, title: "hello")

      assert {:ok, %{title: "hello"}} = WithBoundedString.dump(value_object)
    end

    test "the dumped value object is JSON encodable" do
      value_object = struct!(WithBoundedString, title: "hello")
      {:ok, dumped} = WithBoundedString.dump(value_object)

      assert {:ok, ~s({"title":"hello"})} = Jason.encode(dumped)
    end

    test "a nil value survives the round trip" do
      value_object = struct!(WithBoundedString, title: nil)

      assert {:ok, %{title: nil}} = WithBoundedString.dump(value_object)
    end

    test "an oversized value built with struct!/2 cannot be dumped" do
      value_object = struct!(WithBoundedString, title: "hello world")

      assert_raise ArgumentError, ~r/cannot dump `"hello world"`/, fn ->
        WithBoundedString.dump(value_object)
      end
    end
  end
end
