defmodule Trogon.Ecto.FieldOptionsTest do
  use ExUnit.Case, async: true

  alias Trogon.Ecto.FieldOptions

  describe "keys/0" do
    test "is every option Ecto's field/3 documents, plus the two Ecto injects" do
      assert FieldOptions.keys() == [
               :default,
               :source,
               :autogenerate,
               :read_after_writes,
               :virtual,
               :primary_key,
               :load_in_query,
               :redact,
               :skip_default_validation,
               :writable,
               :on_writable_violation,
               :field,
               :schema
             ]
    end

    test "every key is one Ecto's own field/3 accepts" do
      for {key, value} <- [
            default: "x",
            source: :aa,
            autogenerate: false,
            read_after_writes: false,
            virtual: false,
            primary_key: false,
            load_in_query: true,
            redact: true,
            skip_default_validation: true,
            writable: :always,
            on_writable_violation: :raise
          ] do
        assert key in FieldOptions.keys()

        defmodule_with_field = """
        defmodule EctoAccepts#{key} do
          use Ecto.Schema
          @primary_key false
          embedded_schema do
            field :a, :string, #{key}: #{inspect(value)}
          end
        end
        """

        assert [_ | _] = Code.compile_string(defmodule_with_field)
      end
    end

    test "excludes the association options Ecto's private @field_opts also lists" do
      for key <- [:foreign_key, :on_replace, :defaults, :type, :where, :references] do
        refute key in FieldOptions.keys()
      end
    end
  end

  describe "nimble_schema/0" do
    test "accepts any value and stays out of the generated docs" do
      schema = FieldOptions.nimble_schema()

      assert Keyword.keys(schema) == FieldOptions.keys()
      assert Enum.all?(schema, fn {_key, spec} -> spec == [type: :any, doc: false] end)
      assert NimbleOptions.docs(NimbleOptions.new!(schema)) == ""
    end
  end
end
