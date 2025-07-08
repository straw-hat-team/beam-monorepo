defmodule Trogon.Ecto.Schema do
  @moduledoc """
  Extends a `Ecto.Schema` module with functionality.
  """

  alias Ecto.Changeset

  @doc """
  Extends a `Ecto.Schema` module with some functionality.

      defmodule MySchema do
        use Ecto.Schema
        use Trogon.Ecto.Schema

        embedded_schema do
          field :title, :string
          # ...
        end
      end

  The following functions are available in the module now:

  `new/1`: **overridable** struct factory function. It takes an attribute map
  and runs the `changeset/2`.

  `new!/1`: **overridable** like `new/1` raising an error when the validation
  fails.

  `changeset/2`: **overridable** function. It takes a struct and the attributes
  and returns a `Ecto.Changeset`.
  The default implementation apply a deeply-nested casting over all the fields
  using `Ecto.Changeset.cast/4` and `Ecto.Changeset.cast_embed/4`.
  When `@enforce_keys` is defined, it will apply `Ecto.Changeset.validate_required/3`
  to the list of fields.
  When overriding the function, allows you have full control over the validation
  layer, deactivating all the nested-casting.
  """
  @spec __using__(opts :: []) :: any()
  defmacro __using__(_opts \\ []) do
    quote do
      alias Trogon.Ecto.Schema
      @before_compile Trogon.Ecto.Schema

      @doc """
      Creates a `t:t/0`.
      """
      @spec new(attrs :: map()) :: {:ok, %__MODULE__{}}
      def new(attrs) do
        Trogon.Ecto.Schema.__new__(__MODULE__, attrs)
      end

      @doc """
      Creates a `t:t/0`.
      """
      @spec new!(attrs :: map()) :: %__MODULE__{}
      def new!(attrs) do
        Trogon.Ecto.Schema.__new__!(__MODULE__, attrs)
      end

      @doc false
      @spec validate(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
      def validate(%Ecto.Changeset{} = changeset, attrs) do
        changeset
      end

      @doc """
      Returns an `t:Ecto.Changeset.t/0` for a given `t:t/0` model.
      """
      @spec changeset(message :: %__MODULE__{}, attrs :: map()) :: Ecto.Changeset.t()
      def changeset(message, attrs) do
        message
        |> Schema.changeset(attrs)
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

      defoverridable new: 1,
                     new!: 1,
                     changeset: 2,
                     validate: 2,
                     type: 0,
                     cast: 1,
                     load: 1,
                     dump: 1
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
    use Trogon.Ecto.Schema

    @enforce_keys [:title, :amount]
    embedded_schema do
      field :title, :string
      field :amount, :integer
    end

    def changeset(message, attrs) do
      message
      |> Trogon.Ecto.Schema.changeset(attrs)
      |> Changeset.validate_number(:amount, greater_than: 0)
    end
  end
  ```
  """
  def changeset(%struct_module{} = model, attrs) do
    embeds = struct_module.__schema__(:embeds)
    fields = struct_module.__schema__(:fields)

    changeset =
      model
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
