defmodule OnePiece.Commanded.Enum do
  @moduledoc """
  Defines an Enum type module.
  """

  @doc """
  Converts the module into a struct with an `:value` enum field.

  ## Using

  - `Ecto.Schema`
  - `Ecto.Type`

  ## Derives

  - `Jason.Encoder`

  ## Usage

      defmodule BankAccountType do
        use OnePiece.Commanded.Enum, values: [:business, :personal]
      end

      {:ok, type} = BankAccountType.new(:business)

  You can use it in your `Ecto.Schema` like this:

      defmodule BankAccount do
        use Ecto.Schema

        embedded_schema do
          field :type, BankAccountType
        end
      end
  """
  defmacro __using__(opts) do
    values = Keyword.fetch!(opts, :values)
    type_ast = Enum.reduce(values, &{:|, [], [&1, &2]})

    value_functions_ast =
      for value <- values do
        quote do
          def unquote(value)(), do: %__MODULE__{value: unquote(value)}
        end
      end

    load_functions_ast =
      for value <- values do
        quote do
          @impl Ecto.Type
          def load(unquote(Atom.to_string(value))) do
            {:ok, %__MODULE__{value: unquote(value)}}
          end
        end
      end

    dump_functions_ast =
      for value <- values do
        value_string = Atom.to_string(value)

        quote do
          @impl Ecto.Type
          def dump(%__MODULE__{value: unquote(value)}) do
            {:ok, unquote(value_string)}
          end
        end
      end

    cast_as_function_ast =
      for value <- values do
        value_string = Atom.to_string(value)

        quote do
          @impl Ecto.Type
          def cast(unquote(value_string)) do
            {:ok, %__MODULE__{value: unquote(value)}}
          end
        end
      end

    quote generated: true do
      alias OnePiece.Commanded.ValueObject
      alias Ecto.Changeset

      use Ecto.Schema
      use Ecto.Type

      @primary_key false
      @enforce_keys [:value]
      embedded_schema do
        field :value, Ecto.Enum, values: unquote(values)
      end

      @type value :: unquote(type_ast)
      @type t :: %__MODULE__{value: value()}

      @doc """
      Creates a `t:t/0`.
      """
      @spec new(attrs :: %{required(:value) => value()}) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
      def new(attrs) when is_map(attrs) do
        ValueObject.__new__(__MODULE__, attrs)
      end

      @spec new(value :: value()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
      def new(value) do
        ValueObject.__new__(__MODULE__, %{value: value})
      end

      @doc """
      Creates a `t:t/0`.
      """
      @spec new!(attrs :: %{required(:value) => value()}) :: %__MODULE__{}
      def new!(attrs) when is_map(attrs) do
        ValueObject.__new__!(__MODULE__, attrs)
      end

      @spec new!(value :: value()) :: %__MODULE__{}
      def new!(value) do
        ValueObject.__new__!(__MODULE__, %{value: value})
      end

      @doc """
      Returns an `t:Ecto.Changeset.t/0` for a given `t:t/0` value object.
      """
      @spec changeset(message :: %__MODULE__{}, attrs :: %{required(:value) => value()}) :: Ecto.Changeset.t()
      def changeset(message, attrs) do
        message
        |> Changeset.cast(attrs, [:value])
        |> Changeset.validate_required([:value])
      end

      @spec values() :: [unquote(type_ast)]
      def values, do: unquote(values)

      unquote_splicing(value_functions_ast)

      @impl Ecto.Type
      def type, do: :string

      @impl Ecto.Type
      def cast(value) when is_struct(value, __MODULE__) do
        {:ok, value}
      end

      unquote_splicing(cast_as_function_ast)

      @impl Ecto.Type
      def cast(value) when value in unquote(values) do
        {:ok, %__MODULE__{value: value}}
      end

      @impl Ecto.Type
      def cast(_), do: :error

      unquote_splicing(load_functions_ast)
      @impl Ecto.Type
      def load(_), do: :error

      unquote_splicing(dump_functions_ast)
      @impl Ecto.Type
      def dump(_), do: :error

      @impl Ecto.Type
      def equal?(%__MODULE__{value: value1}, %__MODULE__{value: value1}) do
        true
      end

      @impl Ecto.Type
      def equal?(_term1, _term2), do: false

      defimpl Jason.Encoder do
        def encode(v, opts) do
          Jason.Encode.value(v.value, opts)
        end
      end
    end
  end
end
