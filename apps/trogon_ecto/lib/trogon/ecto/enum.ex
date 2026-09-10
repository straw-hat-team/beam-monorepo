defmodule Trogon.Ecto.Enum do
  @moduledoc """
  Defines an Enum type module.
  """

  @doc """
  Converts the module into a struct with an `:value` enum field.

  ## Using

  - `Ecto.Schema`
  - `Ecto.Type`

  ## Usage

      defmodule BankAccountType do
        use Trogon.Ecto.Enum, values: [:business, :personal]
      end

      {:ok, type} = BankAccountType.new(:business)

  You can use it in your `Ecto.Schema` like this:

      defmodule BankAccount do
        use Ecto.Schema

        embedded_schema do
          field :type, BankAccountType
        end
      end

  ## Protocols

  The generated module always implements `String.Chars`, rendering as the
  string form of its `:value`, the same form `dump/1` returns.

  It also implements `Jason.Encoder`, `JSON.Encoder`, `Phoenix.Param` and
  `Phoenix.HTML.Safe` when each is available, so an enum can be encoded,
  used in a route helper, or rendered in a template without the consumer
  taking on any of those dependencies.
  """
  @spec __using__(opts :: Keyword.t()) :: Macro.t()
  defmacro __using__(opts) do
    values = Keyword.fetch!(opts, :values)

    quote generated: true do
      unquote(__generated_schema__(values))
      unquote(__generated_constructors__())
      unquote(__generated_changeset__())
      unquote(__generated_values__(values))
      unquote(__generated_ecto_type__())
      unquote(__generated_ecto_cast__(values))
      unquote(__generated_ecto_load__(values))
      unquote(__generated_ecto_dump__(values))
      unquote(__generated_ecto_comparison__())
      unquote(__generated_protocols__())
    end
  end

  defp __generated_schema__(values) do
    type_ast = Enum.reduce(values, &{:|, [], [&1, &2]})

    quote generated: true, location: :keep do
      alias Trogon.Ecto.ValueObject
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
    end
  end

  defp __generated_constructors__ do
    quote generated: true, location: :keep do
      @doc """
      Creates a `t:t/0`.
      """
      @spec new(attrs :: %{required(:value) => value()}) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
      @spec new(value :: value()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
      def new(%__MODULE__{} = value), do: ValueObject.new(__MODULE__, Map.from_struct(value))
      def new(attrs) when is_map(attrs), do: ValueObject.new(__MODULE__, attrs)
      def new(value), do: ValueObject.new(__MODULE__, %{value: value})

      @doc """
      Creates a `t:t/0`.
      """
      @spec new!(attrs :: %{required(:value) => value()}) :: %__MODULE__{}
      @spec new!(value :: value()) :: %__MODULE__{}
      def new!(%__MODULE__{} = value), do: ValueObject.new!(__MODULE__, Map.from_struct(value))
      def new!(attrs) when is_map(attrs), do: ValueObject.new!(__MODULE__, attrs)
      def new!(value), do: ValueObject.new!(__MODULE__, %{value: value})
    end
  end

  defp __generated_changeset__ do
    quote generated: true, location: :keep do
      @doc """
      Returns an `t:Ecto.Changeset.t/0` for a given `t:t/0` value object.
      """
      @spec changeset(message :: %__MODULE__{}, attrs :: %{required(:value) => value()}) :: Ecto.Changeset.t()
      def changeset(message, attrs) do
        message
        |> Changeset.cast(attrs, [:value])
        |> Changeset.validate_required([:value])
      end
    end
  end

  defp __generated_values__(values) do
    type_ast = Enum.reduce(values, &{:|, [], [&1, &2]})

    value_functions =
      for value <- values do
        quote generated: true, location: :keep do
          @doc """
          Returns the `#{inspect(unquote(value))}` `t:t/0`.
          """
          @spec unquote(value)() :: t()
          def unquote(value)(), do: %__MODULE__{value: unquote(value)}
        end
      end

    quote generated: true, location: :keep do
      @doc """
      Returns every supported value.
      """
      @spec values() :: [unquote(type_ast)]
      def values, do: unquote(values)

      unquote_splicing(value_functions)
    end
  end

  defp __generated_ecto_type__ do
    quote generated: true, location: :keep do
      @impl Ecto.Type
      def type, do: :string
    end
  end

  defp __generated_ecto_cast__(values) do
    value_clauses =
      for value <- values do
        quote generated: true, location: :keep do
          def cast(unquote(Atom.to_string(value))), do: {:ok, %__MODULE__{value: unquote(value)}}
        end
      end

    quote generated: true, location: :keep do
      @impl Ecto.Type
      def cast(%__MODULE__{value: value} = enum) when value in unquote(values), do: {:ok, enum}
      def cast(%{value: value}), do: cast(value)
      unquote_splicing(value_clauses)
      def cast(value) when value in unquote(values), do: {:ok, %__MODULE__{value: value}}
      def cast(_), do: :error
    end
  end

  defp __generated_ecto_load__(values) do
    value_clauses =
      for value <- values do
        quote generated: true, location: :keep do
          def load(unquote(Atom.to_string(value))), do: {:ok, %__MODULE__{value: unquote(value)}}
        end
      end

    quote generated: true, location: :keep do
      @impl Ecto.Type
      unquote_splicing(value_clauses)
      def load(_), do: :error
    end
  end

  defp __generated_ecto_dump__(values) do
    quote generated: true, location: :keep do
      @impl Ecto.Type
      @spec dump(any()) :: {:ok, String.t()} | :error
      def dump(%__MODULE__{value: value}) when value in unquote(values), do: {:ok, Atom.to_string(value)}
      def dump(_), do: :error
    end
  end

  defp __generated_ecto_comparison__ do
    quote generated: true, location: :keep do
      @impl Ecto.Type
      def equal?(%__MODULE__{value: value}, %__MODULE__{value: value}), do: true
      def equal?(_term1, _term2), do: false
    end
  end

  defp __generated_protocols__ do
    quote generated: true, location: :keep do
      unquote(__generated_string_chars_impl__())
      unquote(__generated_jason_impl__())
      unquote(__generated_json_impl__())
      unquote(__generated_phoenix_param_impl__())
      unquote(__generated_phoenix_html_safe_impl__())
    end
  end

  defp __generated_string_chars_impl__ do
    quote location: :keep do
      defimpl String.Chars do
        @moduledoc false
        def to_string(%@for{value: value}) when is_atom(value), do: Atom.to_string(value)
      end
    end
  end

  defp __generated_jason_impl__ do
    quote location: :keep do
      if Code.ensure_loaded?(Jason.Encoder) do
        defimpl Jason.Encoder do
          @moduledoc false
          def encode(%@for{value: value}, opts) when is_atom(value) do
            Jason.Encode.string(Atom.to_string(value), opts)
          end
        end
      end
    end
  end

  defp __generated_json_impl__ do
    quote location: :keep do
      if Code.ensure_loaded?(JSON.Encoder) do
        defimpl JSON.Encoder do
          @moduledoc false
          def encode(%@for{value: value}, encoder) when is_atom(value) do
            encoder.(Atom.to_string(value), encoder)
          end
        end
      end
    end
  end

  defp __generated_phoenix_param_impl__ do
    quote location: :keep do
      if Code.ensure_loaded?(Phoenix.Param) do
        defimpl Phoenix.Param do
          @moduledoc false
          def to_param(%@for{value: value} = enum) when is_atom(value), do: Kernel.to_string(enum)
        end
      end
    end
  end

  defp __generated_phoenix_html_safe_impl__ do
    quote location: :keep do
      if Code.ensure_loaded?(Phoenix.HTML.Safe) do
        defimpl Phoenix.HTML.Safe do
          @moduledoc false
          def to_iodata(%@for{value: value} = enum) when is_atom(value) do
            Phoenix.HTML.Safe.to_iodata(Kernel.to_string(enum))
          end
        end
      end
    end
  end
end
