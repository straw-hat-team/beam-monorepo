defmodule OnePiece.Commanded.Enum do
  @moduledoc """
  Enum  module with added macros to define a type and check supported values.
  """

  defmacro __using__(opts) do
    values = Keyword.fetch!(opts, :values)
    type_ast = Enum.reduce(values, &{:|, [], [&1, &2]})

    value_functions_ast =
      for value <- values do
        quote do
          def unquote(value)(), do: unquote(value)
        end
      end

    load_functions_ast =
      for value <- values do
        quote do
          def load(unquote(Atom.to_string(value))) do
            {:ok, unquote(value)}
          end
        end
      end

    dump_functions_ast =
      for value <- values do
        quote do
          def dump(unquote(value)) do
            {:ok, Atom.to_string(unquote(value))}
          end
        end
      end

    cast_as_function_ast =
      for value <- values do
        quote do
          def cast(unquote(Atom.to_string(value))) do
            {:ok, unquote(value)}
          end
        end
      end

    quote generated: true do
      use Ecto.Type

      @type t :: unquote(type_ast)

      @spec values() :: [t()]
      def values, do: unquote(values)

      unquote_splicing(value_functions_ast)

      def type, do: :string

      unquote_splicing(cast_as_function_ast)

      def cast(value) when value in unquote(values) do
        {:ok, value}
      end

      def cast(_), do: :error

      unquote_splicing(load_functions_ast)
      def load(_), do: :error

      unquote_splicing(dump_functions_ast)
      def dump(_), do: :error
    end
  end
end
