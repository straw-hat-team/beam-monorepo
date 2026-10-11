defmodule Trogon.Commanded.Enum do
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
        use Trogon.Commanded.Enum, values: [:business, :personal]
      end

      {:ok, type} = BankAccountType.new(:business)

  You can use it in your `Ecto.Schema` like this:

      defmodule BankAccount do
        use Ecto.Schema

        embedded_schema do
          field :type, BankAccountType
        end
      end

  ## Proto-driven Enum

  You can derive values from a protobuf enum module instead of a hardcoded list:

      defmodule ObjectTypeEnum do
        use Trogon.Commanded.Enum,
          proto: Acme.Type.V1.ObjectType
      end

  The enum values are derived at compile time, sorted by their proto field number.

  A proto enum carries a zero value that rarely belongs in a value object, so
  the module accepts `:except` to drop values from the derived list:

      defmodule ObjectTypeEnum do
        use Trogon.Commanded.Enum,
          proto: {Acme.Type.V1.ObjectType, except: [:OBJECT_TYPE_UNSPECIFIED]}
      end

  `:except` rejects names the proto enum does not define, so a renamed or
  removed proto value fails the build instead of silently widening the enum.

  `:values` and `:proto` are mutually exclusive.
  """
  defmacro __using__(opts) do
    values =
      opts
      |> resolve_proto_options(__CALLER__)
      |> Keyword.fetch!(:values)

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
      alias Trogon.Commanded.ValueObject
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
        ValueObject.new(__MODULE__, attrs)
      end

      @spec new(value :: value()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
      def new(value) do
        ValueObject.new(__MODULE__, %{value: value})
      end

      @doc """
      Creates a `t:t/0`.
      """
      @spec new!(attrs :: %{required(:value) => value()}) :: %__MODULE__{}
      def new!(attrs) when is_map(attrs) do
        ValueObject.new!(__MODULE__, attrs)
      end

      @spec new!(value :: value()) :: %__MODULE__{}
      def new!(value) do
        ValueObject.new!(__MODULE__, %{value: value})
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

      @impl Ecto.Type
      def cast(%{value: value}) do
        cast(value)
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

  defp resolve_proto_options(opts, caller) do
    case {Keyword.has_key?(opts, :values), Keyword.has_key?(opts, :proto)} do
      {true, true} ->
        raise ArgumentError, "expected either :values or :proto, got both"

      {_has_values, false} ->
        opts

      {false, true} ->
        {proto, opts} = Keyword.pop(opts, :proto)
        Keyword.put(opts, :values, proto_values(proto, caller))
    end
  end

  defp proto_values(proto, caller) do
    {module, proto_opts} = proto_source(proto, caller)
    values = module.mapping() |> Map.keys() |> Enum.sort_by(&module.value/1)
    except = proto_except!(module, proto_opts, values)

    values
    |> Enum.reject(&(&1 in except))
    |> ensure_any_value!(module)
  end

  defp proto_source({module, proto_opts}, caller) when is_list(proto_opts) do
    {proto_module!(Macro.expand(module, caller)), proto_opts}
  end

  defp proto_source(module, caller) do
    {proto_module!(Macro.expand(module, caller)), []}
  end

  defp proto_module!(nil) do
    raise ArgumentError, "expected :proto to be a protobuf enum module, got: nil"
  end

  defp proto_module!(module) when is_atom(module) do
    Code.ensure_compiled!(module)

    if Code.ensure_loaded?(module) and function_exported?(module, :mapping, 0) and
         function_exported?(module, :value, 1) do
      module
    else
      raise ArgumentError, "expected :proto to be a protobuf enum module, got: #{inspect(module)}"
    end
  end

  defp proto_module!(module) do
    raise ArgumentError, "expected :proto to be a module, got: #{Macro.to_string(module)}"
  end

  defp proto_except!(module, proto_opts, values) do
    case Keyword.split(proto_opts, [:except]) do
      {_except, [{key, _value} | _rest]} ->
        raise ArgumentError, "unknown option #{inspect(key)} given to :proto, expected :except"

      {except, []} ->
        proto_names!(module, Keyword.get(except, :except, []), values)
    end
  end

  defp proto_names!(module, names, values) when is_list(names) do
    case names -- values do
      [] ->
        names

      unknown ->
        raise ArgumentError, "#{inspect(module)} does not define the enum values: #{inspect(unknown)}"
    end
  end

  defp proto_names!(_module, names, _values) do
    raise ArgumentError, "expected a list of enum values, got: #{inspect(names)}"
  end

  defp ensure_any_value!([], module) do
    raise ArgumentError, "filtering #{inspect(module)} left an empty enum"
  end

  defp ensure_any_value!(values, _module), do: values
end
