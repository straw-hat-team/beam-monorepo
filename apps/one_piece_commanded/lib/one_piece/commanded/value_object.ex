defmodule OnePiece.Commanded.ValueObject do
  @moduledoc """
  Defines "Value Object" modules.
  """

  alias Ecto.Changeset

  @doc """
  Converts the module into an `Ecto.Schema` and add factory functions to create structs.

  ## Using

  - `Ecto.Schema`
  - `Ecto.Type`

  ## Derives

  - `Jason.Encoder`

  ## Usage

  ```elixir
  defmodule MyValueObject do
    use OnePiece.Commanded.ValueObject

    embedded_schema do
      field :title, :string
      # ...
    end
  end
  ```

  ## Overridable

  - `validate/2` to add custom validation to the existing `changeset/2` without overriding the whole `changeset/2`
    function.

      ```elixir
      defmodule MyValueObject do
        use OnePiece.Commanded.ValueObject

        embedded_schema do
          field :amount, :integer
        end

        def validate(changeset, attrs) do
          changeset
          |> Changeset.validate_number(:amount, greater_than: 0)
        end
      end
      ```

  - `changeset/2` returns an `t:Ecto.Changeset.t/0` for a given value object struct.

      > #### Overriding Changeset {: .warning}
      >
      > Be careful when overriding `changeset/2` because the default
      > implementation takes care of `cast`, `validate_required` the
      > `@enforced_keys` and nested embeds. You may want to call
      > `OnePiece.Commanded.ValueObject.changeset/2` to have such features.
      >
      > If you only need to extend the changeset, you can override the
      > `validate/2` function instead.
  """
  @spec __using__(opts :: []) :: any()
  defmacro __using__(_opts \\ []) do
    quote generated: true do
      alias OnePiece.Commanded.ValueObject
      alias Ecto.Changeset

      use Ecto.Schema
      use Ecto.Type

      @derive Jason.Encoder
      @primary_key false

      @before_compile OnePiece.Commanded.ValueObject

      @doc """
      Creates a `t:t/0`.
      """
      @spec new(attrs :: map()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
      def new(attrs) do
        ValueObject.__new__(__MODULE__, attrs)
      end

      @doc """
      Creates a `t:t/0`.
      """
      @spec new!(attrs :: map()) :: %__MODULE__{}
      def new!(attrs) do
        ValueObject.__new__!(__MODULE__, attrs)
      end

      @doc false
      @spec validate(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
      def validate(%Ecto.Changeset{} = changeset, attrs) do
        changeset
      end

      @doc false
      @spec changeset(message :: %__MODULE__{}, attrs :: map()) :: Ecto.Changeset.t()
      def changeset(message, attrs) do
        message
        |> ValueObject.changeset(attrs)
        |> validate(attrs)
      end

      def type, do: :map

      def cast(value) when is_struct(value, __MODULE__), do: {:ok, value}

      def cast(value) when is_map(value) do
        with {:error, _} <- new(value), do: :error
      end

      def cast(_), do: :error

      def load(data) when is_map(data) do
        with {:error, _} <- new(data), do: :error
      end

      def load(_), do: :error

      def dump(value) when is_struct(value, __MODULE__), do: {:ok, Map.from_struct(value)}
      def dump(_), do: :error

      defoverridable new: 1, new!: 1, changeset: 2, validate: 2
    end
  end

  defmacro __before_compile__(env) do
    enforced_keys = get_enforced_keys(env)

    quote unquote: false, bind_quoted: [enforced_keys: enforced_keys] do
      def __enforced_keys__ do
        unquote(enforced_keys)
      end

      for the_key <- enforced_keys do
        def __enforced_keys__?(unquote(the_key)) do
          true
        end
      end

      def __enforced_keys__?(_) do
        false
      end
    end
  end

  defp get_enforced_keys(env) do
    enforce_keys = Module.get_attribute(env.module, :enforce_keys) || []
    enforce_keys ++ get_primary_key_name(env)
  end

  defp get_primary_key_name(env) do
    case Module.get_attribute(env.module, :primary_key) do
      {field_name, _, _} -> [field_name]
      _ -> []
    end
  end

  def __new__(struct_module, attrs) do
    struct_module
    |> apply_changeset(attrs)
    |> Changeset.apply_action(:new)
  end

  def __new__!(struct_module, attrs) do
    struct_module
    |> apply_changeset(attrs)
    |> Changeset.apply_action!(:new)
  end

  @doc """
  Returns an `t:Ecto.Changeset.t/0` for a given value object struct.

  It reads the `@enforced_keys` from the struct and validates the required
  fields. Also, it casts the embeds. It is useful when you override the
  `changeset/2` function in your value object.

  ## Examples

  ```elixir
  defmodule MyValueObject do
    use OnePiece.Commanded.ValueObject

    @enforce_keys [:title, :amount]
    embedded_schema do
      field :title, :string
      field :amount, :integer
    end

    def changeset(message, attrs) do
      message
      |> ValueObject.changeset(attrs)
      |> Changeset.validate_number(:amount, greater_than: 0)
    end
  end
  ```
  """
  def changeset(%struct_module{} = message, attrs) do
    embeds = struct_module.__schema__(:embeds)
    fields = struct_module.__schema__(:fields)

    changeset =
      message
      |> Changeset.cast(from_struct(attrs), fields -- embeds)
      |> Changeset.validate_required(struct_module.__enforced_keys__() -- embeds)

    Enum.reduce(
      embeds,
      changeset,
      &cast_embed(&1, &2, struct_module)
    )
  end

  defp cast_embed(field, changeset, struct_module) do
    Changeset.cast_embed(changeset, field, required: struct_module.__enforced_keys__?(field))
  end

  defp from_struct(value) when is_struct(value) do
    # https://github.com/elixir-ecto/ecto/issues/4168
    Map.from_struct(value)
  end

  defp from_struct(value), do: value

  defp apply_changeset(struct_module, attrs) do
    struct(struct_module)
    |> struct_module.changeset(attrs)
  end
end
