defmodule Trogon.Commanded.UnionObjectId do
  @moduledoc """
  Discriminated union type that can hold any of multiple `Trogon.Commanded.ObjectId` types.
  """

  @using_opts_schema NimbleOptions.new!(
                       types: [
                         type: {:list, :atom},
                         required: true,
                         doc: "List of ObjectId modules that can be held by this union."
                       ]
                     )

  @doc """
  Defines a union type that can hold any of the specified ObjectId types.

  Creates a discriminated union that combines multiple ObjectId types into a single field.
  The prefix of each ObjectId determines which type it is when parsing from storage.

  ## Options

  #{NimbleOptions.docs(@using_opts_schema)}

  ## Usage

  First, define individual ObjectId types:

      defmodule MyApp.TenantId do
        use Trogon.Commanded.ObjectId, object_type: "tenant"
      end

      defmodule MyApp.SystemId do
        use Trogon.Commanded.ObjectId, object_type: "system"
      end

  Then, create a union that combines them:

      defmodule MyApp.PrincipalId do
        use Trogon.Commanded.UnionObjectId,
          types: [MyApp.TenantId, MyApp.SystemId]
      end

  Use the union:

      iex> tenant_id = MyApp.TenantId.new("abc-123")
      iex> principal = MyApp.PrincipalId.new(tenant_id)
      %MyApp.PrincipalId{id: %MyApp.TenantId{id: "abc-123"}}

      iex> MyApp.PrincipalId.parse("tenant_abc-123")
      {:ok, %MyApp.PrincipalId{id: %MyApp.TenantId{id: "abc-123"}}}

      iex> to_string(principal)
      "tenant_abc-123"

  ## Type Safety

  The union preserves the type of the inner ObjectId, so you can pattern match to determine
  which variant you have:

      iex> case principal.id do
      ...>   %MyApp.TenantId{} -> "Got a tenant!"
      ...>   %MyApp.SystemId{} -> "Got a system!"
      ...> end
      "Got a tenant!"

  ## Storage Format

  The union stores the complete prefixed string (e.g., `"tenant_abc-123"`). The prefix is
  essential for type identification when parsing. Without it, the union cannot determine
  which type to deserialize to.

      iex> MyApp.PrincipalId.to_storage(principal)
      "tenant_abc-123"

  ## Ecto Integration

  The union implements `Ecto.Type`, so you can use it directly in Ecto schemas:

      defmodule MyApp.Event do
        use Ecto.Schema

        schema "events" do
          field :actor_id, MyApp.PrincipalId
        end
      end

  ## Compile-Time Validation

  The macro validates your union definition at compile time:

  - **Non-empty types list**: At least one ObjectId type must be provided
  - **No exact prefix duplicates**: No two types can have the same prefix

  > #### Warning {: .warning}
  >
  > **Prefix Overlaps Are Not Caught at Compile Time**
  >
  > Compile-time validation only catches **exact prefix duplicates**, not partial overlaps.
  > If one prefix is a substring of another, the shorter prefix will match first during parsing,
  > causing silent type mismatches.
  >
  > **Example of the Problem:**
  >
  > ```elixir
  > defmodule AcmeId do
  >   use Trogon.Commanded.ObjectId, object_type: "acme"  # prefix: "acme_"
  > end
  >
  > defmodule AcmeAdminId do
  >   use Trogon.Commanded.ObjectId, object_type: "acme_admin"  # prefix: "acme_admin_"
  > end
  >
  > defmodule PrincipalId do
  >   use Trogon.Commanded.UnionObjectId, types: [AcmeId, AcmeAdminId]
  > end
  >
  > # This compiles but gives the wrong result:
  > PrincipalId.parse("acme_admin_xyz")
  > # => {:ok, %PrincipalId{id: %AcmeId{id: "admin_xyz"}}}  ❌ WRONG!
  > # Should be: %PrincipalId{id: %AcmeAdminId{id: "xyz"}}
  > ```
  >
  > **How to Avoid:**
  >
  > Design ObjectId prefixes to be semantically distinct and non-overlapping:
  > - ✅ Good: `"tenant"`, `"system"`, `"service"`
  > - ❌ Bad: `"acme"`, `"acme_admin"` (one is substring of other)
  > - ❌ Bad: `"app"`, `"apple"` (one is substring of other)
  """
  defmacro __using__(opts) do
    # Expand module aliases before validation
    types =
      opts
      |> Keyword.fetch!(:types)
      |> Enum.map(&Macro.expand(&1, __CALLER__))

    opts = Keyword.put(opts, :types, types)
    opts = NimbleOptions.validate!(opts, @using_opts_schema)
    types = Keyword.fetch!(opts, :types)

    if Enum.empty?(types) do
      raise CompileError,
        description: "UnionObjectId types list cannot be empty. Provide at least one ObjectId type."
    end

    # Compile-time check: ensure no overlapping prefixes
    validate_no_prefix_collisions(types)

    quote location: :keep do
      @behaviour Ecto.Type

      @type t :: %__MODULE__{id: struct()}

      defstruct [:id]

      unquote(__generated_new_functions__(types))
      unquote(__generated_parse_functions__(types))
      unquote(__generated_storage_functions__(types))
      unquote(__generated_ecto_cast__())
      unquote(__generated_ecto_load__())
      unquote(__generated_ecto_dump__())
      unquote(__generated_ecto_comparison__())
      unquote(__generated_protocols__())
    end
  end

  defp __generated_new_functions__(types) do
    quote location: :keep do
      @doc """
      Wraps an existing ObjectId struct into the union.

      The passed struct must be one of the union's types.

      ## Examples

          iex> obj_id = #{unquote(Enum.at(types, 0))}.new("abc-123")
          iex> #{inspect(__MODULE__)}.new(obj_id)
          %#{inspect(__MODULE__)}{id: %#{unquote(Enum.at(types, 0))}{id: "abc-123"}}
      """
      unquote(
        for module <- types do
          quote do
            @spec new(unquote(module).t()) :: t()
            def new(%unquote(module){} = id), do: %__MODULE__{id: id}
          end
        end
      )
    end
  end

  defp __generated_parse_functions__(types) do
    quote location: :keep do
      @doc """
      Parses a string by trying each underlying type's parse function.

      The string must be in a format recognized by one of the union's types.

      ## Examples

          iex> #{inspect(__MODULE__)}.parse("#{unquote(Enum.at(types, 0)).prefix()}abc-123")
          {:ok, %#{inspect(__MODULE__)}{id: %#{unquote(Enum.at(types, 0))}{id: "abc-123"}}}

          iex> #{inspect(__MODULE__)}.parse("invalid")
          {:error, :invalid_format}
      """
      @spec parse(String.t()) :: {:ok, t()} | {:error, :invalid_format}
      def parse(""), do: {:error, :invalid_format}

      unquote(
        for module <- types do
          prefix = module.prefix()

          quote do
            def parse(unquote(prefix) <> id) when id != "" do
              {:ok, %__MODULE__{id: %unquote(module){id: id}}}
            end
          end
        end
      )

      def parse(_), do: {:error, :invalid_format}
    end
  end

  defp __generated_storage_functions__(types) do
    quote location: :keep do
      @doc """
      Converts the union to a storage string.

      Uses the inner ObjectId's to_string representation, which includes its full prefix.

      ## Examples

          iex> obj_id = #{unquote(Enum.at(types, 0))}.new("abc-123")
          iex> union = #{inspect(__MODULE__)}.new(obj_id)
          iex> #{inspect(__MODULE__)}.to_storage(union)
          "#{unquote(Enum.at(types, 0)).prefix()}abc-123"
      """
      @spec to_storage(t()) :: String.t()
      def to_storage(%__MODULE__{id: id}) when is_struct(id), do: Kernel.to_string(id)
    end
  end

  defp __generated_ecto_cast__() do
    quote location: :keep do
      @impl Ecto.Type
      @spec type() :: :string
      def type, do: :string

      @impl Ecto.Type
      @spec cast(any()) :: {:ok, t() | nil} | :error
      def cast(nil), do: {:ok, nil}
      def cast(""), do: {:ok, nil}
      def cast(%__MODULE__{id: id} = value) when is_struct(id), do: {:ok, value}

      def cast(value) when is_binary(value) do
        case parse(value) do
          {:ok, union} -> {:ok, union}
          {:error, _} -> :error
        end
      end

      def cast(_), do: :error
    end
  end

  defp __generated_ecto_load__() do
    quote location: :keep do
      @impl Ecto.Type
      @spec load(any()) :: {:ok, t() | nil} | :error
      def load(nil), do: {:ok, nil}
      def load(""), do: {:ok, nil}

      def load(value) when is_binary(value) do
        case parse(value) do
          {:ok, union} -> {:ok, union}
          {:error, _} -> :error
        end
      end

      def load(_), do: :error
    end
  end

  defp __generated_ecto_dump__() do
    quote location: :keep do
      @impl Ecto.Type
      @spec dump(any()) :: {:ok, String.t() | nil} | :error
      def dump(nil), do: {:ok, nil}
      def dump(%__MODULE__{id: id} = value) when is_struct(id), do: {:ok, to_storage(value)}
      def dump(_), do: :error
    end
  end

  defp __generated_ecto_comparison__() do
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

  defp __generated_protocols__() do
    quote location: :keep do
      defimpl String.Chars do
        @moduledoc false
        def to_string(%@for{id: id}), do: Kernel.to_string(id)
      end

      if Code.ensure_loaded?(Jason.Encoder) do
        defimpl Jason.Encoder do
          @moduledoc false
          def encode(%@for{id: id}, opts) do
            Jason.Encoder.encode(id, opts)
          end
        end
      end
    end
  end

  @doc false
  defp validate_no_prefix_collisions(types) do
    types
    |> build_prefix_map()
    |> check_duplicate_prefixes()
  end

  @doc false
  defp build_prefix_map(types) do
    types
    |> Enum.map(&module_with_prefix/1)
    |> Enum.group_by(&elem(&1, 1))
  end

  @doc false
  defp module_with_prefix(module) do
    {module, module.prefix()}
  end

  @doc false
  defp check_duplicate_prefixes(prefixes_by_type) do
    Enum.each(prefixes_by_type, &check_prefix_collision/1)
  end

  @doc false
  defp check_prefix_collision({prefix, modules}) do
    if length(modules) > 1 do
      raise_prefix_collision_error(prefix, modules)
    end
  end

  @doc false
  defp raise_prefix_collision_error(prefix, modules) do
    module_names = format_module_names(modules)

    raise CompileError,
      description: "UnionObjectId prefix collision: #{inspect(prefix)} is used by multiple types: #{module_names}"
  end

  @doc false
  defp format_module_names(modules) do
    Enum.map_join(modules, ", ", &elem(&1, 0))
  end
end
