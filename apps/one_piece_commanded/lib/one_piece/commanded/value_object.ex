defmodule OnePiece.Commanded.ValueObject do
  @moduledoc """
  Defines "Value Object" modules.
  """

  alias Ecto.Changeset

  @doc """
  Converts the module into an `Ecto.Schema`.

  It derives from `Jason.Encoder` and also adds some factory functions to create
  structs.

  ## Usage

      defmodule MyValueObject do
        use OnePiece.Commanded.ValueObject

        embedded_schema do
          field :title, :string
          # ...
        end
      end

      {:ok, my_value} = MyValueObject.new(%{title: "Hello, World!"})
  """
  @spec __using__(opts :: []) :: any()
  defmacro __using__(_opts \\ []) do
    quote do
      alias OnePiece.Commanded.ValueObject

      use Ecto.Schema

      @derive Jason.Encoder
      @primary_key false

      @before_compile OnePiece.Commanded.ValueObject

      @doc """
      Creates a `t:t/0`.
      """
      @spec new(attrs :: map()) :: {:ok, %__MODULE__{}}
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

      @doc """
      Returns an `t:Ecto.Changeset.t/0` for a given `t:t/0` command.
      """
      @spec changeset(message :: %__MODULE__{}, attrs :: map()) :: Ecto.Changeset.t()
      def changeset(message, attrs) do
        ValueObject.__changeset__(message, attrs)
      end

      defoverridable new: 1, new!: 1, changeset: 2
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

  def __changeset__(%struct_module{} = message, attrs) do
    embeds = struct_module.__schema__(:embeds)
    fields = struct_module.__schema__(:fields)

    changeset =
      message
      |> Changeset.cast(attrs, fields -- embeds)
      |> Changeset.validate_required(struct_module.__enforced_keys__() -- embeds)

    Enum.reduce(
      embeds,
      changeset,
      &cast_embed(&1, &2, struct_module, attrs)
    )
  end

  defp cast_embed(field, changeset, struct_module, attrs) do
    case is_struct(attrs[field]) do
      false ->
        Changeset.cast_embed(changeset, field, required: struct_module.__enforced_keys__?(field))

      true ->
        # credo:disable-for-next-line Credo.Check.Design.TagTODO
        # TODO: Validate that the struct is of the correct type.
        #   It may be the case that you passed a completely different struct as the value. We could `cast_embed`
        #   always and fix the `Changeset.cast(attrs, fields -- embeds)` by converting the `attrs` into a map. But it
        #   would be a bit more expensive since it will run the casting for a field that was already casted.
        #   Checking the struct types MAY be enough but taking into consideration `embeds_many` could complicated
        #   things. For now, we'll just assume that the user knows what they're doing.
        Changeset.put_change(changeset, field, attrs[field])
    end
  end

  defp apply_changeset(struct_module, attrs) do
    struct(struct_module)
    |> struct_module.changeset(attrs)
  end
end
