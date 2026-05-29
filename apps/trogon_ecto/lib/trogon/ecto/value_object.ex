defmodule Trogon.Ecto.ValueObject do
  @moduledoc """
  Defines "Value Object" modules.
  """

  alias Ecto.Changeset

  @doc """
  Converts the module into an `Ecto.Schema` and add factory functions to create structs.

  ## Using

  - `Ecto.Schema`
  - `Ecto.Type`

  ## Imports

  `use Trogon.Ecto.ValueObject` imports `PolymorphicEmbed.polymorphic_embeds_one/2`
  and `PolymorphicEmbed.polymorphic_embeds_many/2` so they can be used inside
  `embedded_schema/1`.

  ## Usage

  ```elixir
  defmodule MyValueObject do
    use Trogon.Ecto.ValueObject

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
        use Trogon.Ecto.ValueObject

        embedded_schema do
          field :amount, :integer
        end

        def validate(changeset, _attrs) do
          Ecto.Changeset.validate_number(changeset, :amount, greater_than: 0)
        end
      end
      ```

  - `changeset/2` returns an `t:Ecto.Changeset.t/0` for a given value object struct.

      > #### Overriding Changeset {: .warning}
      >
      > Be careful when overriding `changeset/2` because the default
      > implementation takes care of `cast`, `validate_required` the
      > `@enforced_keys` and nested embeds. You may want to call
      > `Trogon.Ecto.ValueObject.changeset/2` to have such features.
      >
      > If you only need to extend the changeset, you can override the
      > `validate/2` function instead.
  """
  @spec __using__(opts :: Keyword.t()) :: Macro.t()
  defmacro __using__(_opts \\ []) do
    quote generated: true do
      alias Trogon.Ecto.ValueObject
      alias Ecto.Changeset

      use Ecto.Schema
      use Ecto.Type
      import PolymorphicEmbed, only: [polymorphic_embeds_one: 2, polymorphic_embeds_many: 2]

      @primary_key false

      @before_compile Trogon.Ecto.ValueObject

      @doc """
      Creates a `t:t/0`.
      """
      @spec new(attrs :: map() | %__MODULE__{}) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
      def new(attrs) when is_map(attrs) do
        Trogon.Ecto.ValueObject.new(__MODULE__, attrs)
      end

      @doc """
      Creates a `t:t/0`.
      """
      @spec new!(attrs :: map() | %__MODULE__{}) :: %__MODULE__{}
      def new!(attrs) when is_map(attrs) do
        Trogon.Ecto.ValueObject.new!(__MODULE__, attrs)
      end

      @doc false
      @spec validate(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
      def validate(%Ecto.Changeset{} = changeset, _attrs) do
        changeset
      end

      @doc false
      @spec changeset(message :: %__MODULE__{}, attrs :: map() | %__MODULE__{}) :: Ecto.Changeset.t()
      def changeset(_message, attrs) when is_struct(attrs, __MODULE__) do
        Ecto.Changeset.change(attrs)
      end

      def changeset(message, attrs) do
        message
        |> Trogon.Ecto.ValueObject.changeset(attrs)
        |> validate(attrs)
      end

      def type, do: :map

      def cast(value) when is_struct(value, __MODULE__), do: {:ok, value}

      def cast(%other{}) do
        {:error, message: "expected %#{inspect(__MODULE__)}{}, got %#{inspect(other)}{}"}
      end

      def cast(value) when is_map(value) do
        case new(value) do
          {:ok, v} -> {:ok, v}
          {:error, _changeset} -> {:error, message: "is invalid"}
        end
      end

      def cast(_), do: :error

      def load(value) when is_struct(value, __MODULE__), do: {:ok, value}
      def load(%_other{}), do: :error

      def load(data) when is_map(data) do
        {:ok, Ecto.embedded_load(__MODULE__, data, :json)}
      end

      def load(_), do: :error

      def dump(value) when is_struct(value, __MODULE__), do: {:ok, Ecto.embedded_dump(value, :json)}
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
      {field_name, _type, opts} ->
        if Keyword.get(opts, :autogenerate, false), do: [], else: [field_name]

      _ ->
        []
    end
  end

  @doc """
  Creates a value object struct for the given module and attributes.

  This function applies the changeset validation logic defined in the value object
  module and returns either `{:ok, struct}` on success or `{:error, changeset}`
  when validation fails.

  ## Parameters

  - `struct_module` - The value object module that uses `Trogon.Ecto.ValueObject`
  - `attrs` - A map of attributes to create the value object with

  ## Examples

  Creating a simple value object:

      iex> Trogon.Ecto.ValueObject.new(Trogon.Ecto.TestSupport.MessageOne, %{title: "Hello"})
      {:ok, %Trogon.Ecto.TestSupport.MessageOne{title: "Hello"}}

  Creating a value object with validation:

      iex> Trogon.Ecto.ValueObject.new(Trogon.Ecto.TestSupport.TransferableMoney, %{amount: 100, currency: :USD})
      {:ok, %Trogon.Ecto.TestSupport.TransferableMoney{amount: 100, currency: :USD}}

  Validation failure example:

      iex> {:error, changeset} = Trogon.Ecto.ValueObject.new(Trogon.Ecto.TestSupport.TransferableMoney, %{amount: -5, currency: :USD})
      iex> changeset.valid?
      false

  Missing required field:

      iex> {:error, changeset} = Trogon.Ecto.ValueObject.new(Trogon.Ecto.TestSupport.MyValueObject, %{amount: 25})
      iex> changeset.valid?
      false

  Passing an own-type struct returns it unchanged (value objects are immutable):

      iex> Trogon.Ecto.ValueObject.new(Trogon.Ecto.TestSupport.MessageOne, %Trogon.Ecto.TestSupport.MessageOne{title: "Hello"})
      {:ok, %Trogon.Ecto.TestSupport.MessageOne{title: "Hello"}}

  Passing a foreign struct raises an `ArgumentError`.
  """
  @spec new(struct_module :: atom(), attrs :: map() | struct()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def new(struct_module, attrs) when is_atom(struct_module) and is_struct(attrs, struct_module) do
    {:ok, attrs}
  end

  def new(struct_module, %other{}) when is_atom(struct_module) do
    raise ArgumentError,
          "expected attrs to be a map or %#{inspect(struct_module)}{}, got %#{inspect(other)}{}"
  end

  def new(struct_module, attrs) when is_atom(struct_module) and is_map(attrs) do
    struct_module
    |> apply_changeset(attrs)
    |> Changeset.apply_action(:new)
  end

  @doc """
  Creates a value object struct for the given module and attributes, raising on validation errors.

  This function is similar to `new/2` but raises an `Ecto.InvalidChangesetError`
  instead of returning an error tuple when validation fails.

  ## Parameters

  - `struct_module` - The value object module that uses `Trogon.Ecto.ValueObject`
  - `attrs` - A map of attributes to create the value object with

  ## Examples

  Creating a simple value object:

      iex> Trogon.Ecto.ValueObject.new!(Trogon.Ecto.TestSupport.MessageOne, %{title: "Hello"})
      %Trogon.Ecto.TestSupport.MessageOne{title: "Hello"}

  Creating a value object with validation:

      iex> Trogon.Ecto.ValueObject.new!(Trogon.Ecto.TestSupport.TransferableMoney, %{amount: 100, currency: :USD})
      %Trogon.Ecto.TestSupport.TransferableMoney{amount: 100, currency: :USD}

  Validation failure raises an exception:

      iex> try do
      ...>   Trogon.Ecto.ValueObject.new!(Trogon.Ecto.TestSupport.TransferableMoney, %{amount: -5, currency: :USD})
      ...> rescue
      ...>   Ecto.InvalidChangesetError -> :error_raised
      ...> end
      :error_raised

  Missing required field raises an exception:

      iex> try do
      ...>   Trogon.Ecto.ValueObject.new!(Trogon.Ecto.TestSupport.MyValueObject, %{amount: 25})
      ...> rescue
      ...>   Ecto.InvalidChangesetError -> :error_raised
      ...> end
      :error_raised

  Passing an own-type struct returns it unchanged:

      iex> Trogon.Ecto.ValueObject.new!(Trogon.Ecto.TestSupport.MessageOne, %Trogon.Ecto.TestSupport.MessageOne{title: "Hello"})
      %Trogon.Ecto.TestSupport.MessageOne{title: "Hello"}

  Passing a foreign struct raises an `ArgumentError`.
  """
  @spec new!(struct_module :: atom(), attrs :: map() | struct()) :: struct()
  def new!(struct_module, attrs) when is_atom(struct_module) and is_struct(attrs, struct_module) do
    attrs
  end

  def new!(struct_module, %other{}) when is_atom(struct_module) do
    raise ArgumentError,
          "expected attrs to be a map or %#{inspect(struct_module)}{}, got %#{inspect(other)}{}"
  end

  def new!(struct_module, attrs) when is_atom(struct_module) and is_map(attrs) do
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
    use Trogon.Ecto.ValueObject

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
  def changeset(%struct_module{}, %struct_module{} = attrs), do: Changeset.change(attrs)

  def changeset(%struct_module{}, %other{}) when struct_module != other do
    raise ArgumentError,
          "expected attrs to be a map or %#{inspect(struct_module)}{}, got %#{inspect(other)}{}"
  end

  def changeset(%struct_module{} = message, attrs) do
    embeds = struct_module.__schema__(:embeds)
    polymorphic_embeds = get_polymorphic_embeds(struct_module)
    fields = struct_module.__schema__(:fields)
    all_embeds = embeds ++ polymorphic_embeds

    changeset =
      message
      |> Changeset.cast(attrs, fields -- all_embeds)
      |> Changeset.validate_required(struct_module.__enforced_keys__() -- all_embeds)

    changeset
    |> cast_embeds(embeds, struct_module)
    |> cast_polymorphic_embeds(polymorphic_embeds, struct_module)
  end

  defp cast_polymorphic_embeds(changeset, polymorphic_embeds, struct_module) do
    Enum.reduce(
      polymorphic_embeds,
      changeset,
      &cast_polymorphic_embed(&1, &2, struct_module)
    )
  end

  defp cast_embeds(changeset, embeds, struct_module) do
    Enum.reduce(
      embeds,
      changeset,
      &cast_embed(&1, &2, struct_module)
    )
  end

  defp cast_embed(field, changeset, struct_module) do
    Changeset.cast_embed(changeset, field, required: struct_module.__enforced_keys__?(field))
  end

  defp cast_polymorphic_embed(field, changeset, struct_module) do
    PolymorphicEmbed.cast_polymorphic_embed(changeset, field, required: struct_module.__enforced_keys__?(field))
  end

  defp get_polymorphic_embeds(struct_module) do
    :fields
    |> struct_module.__schema__()
    |> Enum.filter(&polymorphic_embed_field?(&1, struct_module))
  end

  defp polymorphic_embed_field?(field, struct_module) do
    case struct_module.__schema__(:type, field) do
      {:parameterized, {PolymorphicEmbed, _config}} -> true
      {:array, {:parameterized, {PolymorphicEmbed, _config}}} -> true
      _ -> false
    end
  end

  defp apply_changeset(struct_module, attrs) do
    struct(struct_module)
    |> struct_module.changeset(attrs)
  end
end
