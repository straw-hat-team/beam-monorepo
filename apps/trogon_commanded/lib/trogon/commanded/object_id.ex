defmodule Trogon.Commanded.ObjectId do
  @moduledoc """
  Macro for defining type-safe, domain-specific object IDs.

  ObjectIds are type-safe identifiers that combine a human-readable prefix with a value,
  stored as `{prefix}{separator}{id}` (e.g., `"user_abc-123"`).

  ## Usage

      defmodule MyApp.UserId do
        use Trogon.Commanded.ObjectId,
          object_type: "user"
      end

      # Create
      user_id = MyApp.UserId.new("abc-123")
      #=> %MyApp.UserId{id: "abc-123"}

      # Convert to string
      to_string(user_id)
      #=> "user_abc-123"

      # Parse
      MyApp.UserId.parse("user_abc-123")
      #=> {:ok, %MyApp.UserId{id: "abc-123"}}

  ## Type Safety

  Each ObjectId type is a separate struct, providing compile-time and runtime type safety:

      def process_user(%MyApp.UserId{} = id), do: ...
      def process_order(%MyApp.OrderId{} = id), do: ...

      process_user(MyApp.OrderId.new("123"))  #=> FunctionClauseError!

  ## Ecto Integration

  ObjectIds implement `Ecto.Type`, so you can use them directly in schemas:

      schema "users" do
        field :id, MyApp.UserId
      end
  """

  @using_opts_schema NimbleOptions.new!(
                       object_type: [
                         type: :string,
                         required: true,
                         doc: "The object type (e.g., `\"user\"`, `\"order\"`)."
                       ],
                       separator: [
                         type: :string,
                         default: "_",
                         doc: "Separator between prefix and id."
                       ],
                       storage_format: [
                         type: {:in, [:full, :drop_prefix]},
                         default: :full,
                         doc: """
                         Database storage format.
                         - `:full` - Store complete string (e.g., `"user_abc-123"`)
                         - `:drop_prefix` - Store only the id (e.g., `"abc-123"`)
                         """
                       ],
                       json_format: [
                         type: {:in, [:full, :drop_prefix]},
                         default: :full,
                         doc: """
                         JSON encoding format.
                         - `:full` - Encode complete string (e.g., `"user_abc-123"`)
                         - `:drop_prefix` - Encode only the id (e.g., `"abc-123"`)
                         """
                       ],
                       validate: [
                         type: {:or, [{:in, [nil, :uuid, :integer]}, {:tuple, [:atom, :atom]}]},
                         default: nil,
                         doc: """
                         Validation for the raw id value (without prefix).
                         - `nil` - No validation (default)
                         - `:uuid` - Validates that the id is a valid UUID
                         - `:integer` - Validates that the id is a valid integer string
                         - `{Module, :function}` - Custom validator (compile-time optimized direct call).
                           The function receives the raw id value and returns `:ok` or `{:error, reason}`.
                         """
                       ]
                     )

  defp expand_validate({module, function}, caller), do: {Macro.expand(module, caller), function}
  defp expand_validate(other, _caller), do: other

  # Validates MF tuple at compile time (if module is available)
  defp validate_mf!({module, function}) do
    cond do
      not Code.ensure_loaded?(module) ->
        # Module not yet compiled (e.g., defined in same file) - skip, will fail at runtime if wrong
        :ok

      not function_exported?(module, function, 1) ->
        raise ArgumentError, "#{inspect(module)}.#{function}/1 is not defined"

      true ->
        :ok
    end
  end

  defp validate_mf!(_), do: :ok

  @doc """
  Defines a type-safe ObjectId module.

  ## Options

  #{NimbleOptions.docs(@using_opts_schema)}

  ## Examples

      defmodule MyApp.UserId do
        use Trogon.Commanded.ObjectId, object_type: "user"
      end

      defmodule MyApp.OrderId do
        use Trogon.Commanded.ObjectId, object_type: "order", separator: "#"
      end

      defmodule MyApp.AccountId do
        use Trogon.Commanded.ObjectId, object_type: "acct", storage_format: :drop_prefix
      end

      # With UUID validation
      defmodule MyApp.ProductId do
        use Trogon.Commanded.ObjectId, object_type: "product", validate: :uuid
      end

      # With integer validation
      defmodule MyApp.SequenceId do
        use Trogon.Commanded.ObjectId, object_type: "seq", validate: :integer
      end

      # With custom validator (compile-time optimized)
      defmodule MyApp.CustomId do
        use Trogon.Commanded.ObjectId,
          object_type: "custom",
          validate: {MyValidator, :check}
      end
  """
  defmacro __using__(opts) do
    opts =
      opts
      |> Keyword.update(:validate, nil, &expand_validate(&1, __CALLER__))
      |> NimbleOptions.validate!(@using_opts_schema)

    object_type = Keyword.fetch!(opts, :object_type)
    separator = Keyword.fetch!(opts, :separator)
    storage_format = Keyword.fetch!(opts, :storage_format)
    json_format = Keyword.fetch!(opts, :json_format)
    validate = Keyword.get(opts, :validate)

    :ok = validate_mf!(validate)

    # Precompute at compile time
    prefix = object_type <> separator
    prefix_len = byte_size(prefix)

    quote location: :keep do
      @behaviour Ecto.Type

      unquote(__generated_struct_and_metadata__(object_type, prefix))
      unquote(__generated_new_function__())
      unquote(__build_validator__(validate))
      unquote(__generated_parse_functions__(prefix, prefix_len, separator, validate))
      unquote(__generated_ecto_cast__())
      unquote(__generated_ecto_load__(storage_format, prefix))
      unquote(__generated_storage_functions__(storage_format, prefix))
      unquote(__generated_ecto_dump__())
      unquote(__generated_ecto_comparison__())
      unquote(__generated_protocols__(prefix, json_format))
    end
  end

  defp __generated_struct_and_metadata__(object_type, prefix) do
    quote location: :keep do
      @type t :: %__MODULE__{id: binary()}

      defstruct [:id]

      @doc false
      @spec object_type() :: String.t()
      def object_type, do: unquote(object_type)

      @doc false
      @spec prefix() :: String.t()
      def prefix, do: unquote(prefix)
    end
  end

  defp __generated_new_function__ do
    quote location: :keep do
      @doc """
      Wraps a value in an ObjectId struct.

      Raises `FunctionClauseError` if value is empty.

      ## Examples

          iex> #{inspect(__MODULE__)}.new("abc-123")
          %#{inspect(__MODULE__)}{id: "abc-123"}
      """
      @spec new(binary()) :: t()
      def new(value) when is_binary(value) and value != "" do
        %__MODULE__{id: value}
      end
    end
  end

  defp __generated_parse_functions__(prefix, prefix_len, separator, validate) do
    quote location: :keep do
      @doc """
      Parses an ObjectId string.

      The string must be in the format `#{unquote(prefix)}{id}`.

      ## Examples

          iex> #{inspect(__MODULE__)}.parse("#{unquote(prefix)}abc-123")
          {:ok, %#{inspect(__MODULE__)}{id: "abc-123"}}

          iex> #{inspect(__MODULE__)}.parse("invalid")
          {:error, :invalid_format}

          iex> #{inspect(__MODULE__)}.parse("wrong#{unquote(separator)}abc-123")
          {:error, :invalid_format}
      """
      @spec parse(String.t()) :: {:ok, t()} | {:error, atom()}
      def parse(string) when is_binary(string) do
        Trogon.Commanded.ObjectId.parse(
          __MODULE__,
          unquote(prefix),
          unquote(prefix_len),
          string,
          unquote(__validator_ref__(validate))
        )
      end

      @doc """
      Parses an ObjectId string, raising on failure.

      Same as `parse/1` but raises `ArgumentError` if the string is invalid.

      ## Examples

          iex> #{inspect(__MODULE__)}.parse!("#{unquote(prefix)}abc-123")
          %#{inspect(__MODULE__)}{id: "abc-123"}

          iex> #{inspect(__MODULE__)}.parse!("invalid")
          ** (ArgumentError) invalid #{inspect(__MODULE__)}: "invalid"
      """
      @spec parse!(String.t()) :: t()
      def parse!(string) when is_binary(string) do
        case parse(string) do
          {:ok, id} -> id
          {:error, _} -> raise ArgumentError, "invalid #{inspect(__MODULE__)}: #{inspect(string)}"
        end
      end
    end
  end

  # Returns nil when no format, function reference when format is specified
  defp __validator_ref__(nil), do: nil
  defp __validator_ref__(_format), do: quote(do: &validate_format/1)

  # No format specified - no validator function generated
  defp __build_validator__(nil), do: nil

  defp __build_validator__(:uuid) do
    quote location: :keep do
      defp validate_format(value) do
        case Uniq.UUID.parse(value) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :invalid_uuid}
        end
      end
    end
  end

  defp __build_validator__(:integer) do
    quote location: :keep do
      defp validate_format(value) do
        case Integer.parse(value) do
          {_, ""} -> :ok
          _ -> {:error, :invalid_integer}
        end
      end
    end
  end

  # MF tuple - generate direct function call (compile-time optimized)
  defp __build_validator__({module, function}) do
    quote location: :keep do
      defp validate_format(value), do: unquote(module).unquote(function)(value)
    end
  end

  defp __generated_ecto_cast__ do
    quote location: :keep do
      @impl Ecto.Type
      @spec type() :: :string
      def type, do: :string

      @impl Ecto.Type
      @spec cast(any()) :: {:ok, t() | nil} | :error | {:error, atom()}
      def cast(nil), do: {:ok, nil}
      def cast(""), do: {:ok, nil}
      def cast(%__MODULE__{id: ""}), do: :error
      def cast(%__MODULE__{id: nil}), do: :error
      def cast(%__MODULE__{id: id} = value) when is_binary(id), do: {:ok, value}
      def cast(value) when is_binary(value), do: parse(value)
      def cast(_), do: :error
    end
  end

  defp __generated_ecto_load__(storage_format, prefix) do
    quote location: :keep do
      @impl Ecto.Type
      @spec load(any()) :: {:ok, t() | nil} | :error
      def load(nil), do: {:ok, nil}
      def load(""), do: {:ok, nil}

      def load(value) when is_binary(value) do
        full_value = Trogon.Commanded.ObjectId.with_prefix(value, unquote(storage_format), unquote(prefix))

        case parse(full_value) do
          {:ok, typeid} -> {:ok, typeid}
          {:error, _} -> :error
        end
      end

      def load(_), do: :error
    end
  end

  defp __generated_storage_functions__(storage_format, prefix) do
    storage_example_output =
      if storage_format == :full, do: inspect(prefix <> "abc-123"), else: inspect("abc-123")

    quote location: :keep do
      @doc """
      Converts an ObjectId struct to a storage format string.

      ## Examples

          iex> #{inspect(__MODULE__)}.to_storage(%#{inspect(__MODULE__)}{id: "abc-123"})
          #{unquote(storage_example_output)}
      """
      @spec to_storage(t()) :: String.t()
      def to_storage(%__MODULE__{id: id}) when is_binary(id) and id != "" do
        Trogon.Commanded.ObjectId.format(unquote(storage_format), unquote(prefix), id)
      end
    end
  end

  defp __generated_ecto_dump__ do
    quote location: :keep do
      @impl Ecto.Type
      @spec dump(any()) :: {:ok, String.t() | nil} | :error
      def dump(nil), do: {:ok, nil}
      def dump(%__MODULE__{id: ""}), do: :error
      def dump(%__MODULE__{id: nil}), do: :error
      def dump(%__MODULE__{id: id} = v) when is_binary(id), do: {:ok, to_storage(v)}
      def dump(_), do: :error
    end
  end

  defp __generated_ecto_comparison__ do
    quote location: :keep do
      @impl Ecto.Type
      @spec equal?(any(), any()) :: boolean()
      def equal?(%__MODULE__{id: a}, %__MODULE__{id: b}), do: a == b
      def equal?(_, _), do: false

      @impl Ecto.Type
      @spec embed_as(atom()) :: :self
      def embed_as(_format), do: :self
    end
  end

  defp __generated_protocols__(prefix, json_format) do
    quote location: :keep do
      defimpl String.Chars do
        @moduledoc false
        def to_string(%@for{id: id}) when is_binary(id) do
          "#{unquote(prefix)}#{id}"
        end
      end

      if Code.ensure_loaded?(Jason.Encoder) do
        defimpl Jason.Encoder do
          @moduledoc false
          def encode(%@for{id: id}, opts) when is_binary(id) do
            value = Trogon.Commanded.ObjectId.format(unquote(json_format), unquote(prefix), id)
            Jason.Encode.string(value, opts)
          end
        end
      end
    end
  end

  @doc false
  @spec parse(module(), String.t(), non_neg_integer(), String.t(), nil | (String.t() -> :ok | {:error, atom()})) ::
          {:ok, struct()} | {:error, atom()}
  def parse(module, prefix, prefix_len, string, validate_format) do
    case string do
      <<^prefix::binary-size(prefix_len), suffix::binary>> when suffix != "" ->
        validate_and_build(module, suffix, validate_format)

      _ ->
        {:error, :invalid_format}
    end
  end

  defp validate_and_build(module, id, nil), do: {:ok, struct(module, id: id)}

  defp validate_and_build(module, id, validate_format) do
    case validate_format.(id) do
      :ok -> {:ok, struct(module, id: id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec format(:full | :drop_prefix, String.t(), String.t()) :: String.t()
  def format(:full, prefix, id), do: prefix <> id
  def format(:drop_prefix, _prefix, id), do: id

  @doc false
  @spec with_prefix(String.t(), :full | :drop_prefix, String.t()) :: String.t()
  def with_prefix(value, :full, _prefix), do: value
  def with_prefix(value, :drop_prefix, prefix), do: prefix <> value
end
