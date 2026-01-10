defmodule Trogon.TypeProvider do
  @moduledoc """
  Provides a type mapping system for converting between string type names and Elixir struct modules.
  """

  alias Trogon.TypeProvider
  alias Trogon.TypeProvider.UnregisteredMappingError

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import TypeProvider, only: [register_type: 2, register_protobuf_message: 1, import_type_provider: 1]

      @type_mapping_prefix Keyword.get(opts, :prefix, "")
      @before_compile TypeProvider

      Module.register_attribute(__MODULE__, :type_mapping, accumulate: true)
    end
  end

  @doc """
  Registers a mapping from a type string to an Elixir Module that defines a struct.

  ## Example

      defmodule MyTypeProvider do
        use Trogon.TypeProvider,
          prefix: "accounts." # optional, adds the prefix to the type

        register_type "account_created", AccountCreated
      end
  """
  @spec register_type(type :: String.t(), struct_mod :: module()) :: Macro.t()
  defmacro register_type(type, struct_mod) do
    quote bind_quoted: [type: type, struct_mod: struct_mod] do
      TypeProvider.__register_type__(
        __MODULE__,
        type,
        struct_mod
      )
    end
  end

  @doc """
  Registers a mapping from a Protobuf message module using its `full_name/0` function as the type.

  This macro requires the Protobuf message module to have a `full_name/0` function that returns
  the fully qualified protobuf type name (e.g., "google.protobuf.Timestamp").

  To generate protobuf modules with `full_name/0`, ensure your protobuf modules are generated
  with the `gen_descriptors=true` option, or define `full_name/0` manually.

  ## Example

      defmodule MyTypeProvider do
        use Trogon.TypeProvider

        # Registers the module using its full_name/0 as the type
        register_protobuf_message MyApp.Proto.AccountCreated
      end

  This is equivalent to:

      register_type "my_app.account_created", MyApp.Proto.AccountCreated

  (assuming `MyApp.Proto.AccountCreated.full_name()` returns `"my_app.account_created"`)
  """
  @spec register_protobuf_message(struct_mod :: module()) :: Macro.t()
  defmacro register_protobuf_message(struct_mod) do
    quote bind_quoted: [struct_mod: struct_mod] do
      TypeProvider.__register_protobuf_message__(
        __MODULE__,
        struct_mod
      )
    end
  end

  @doc """
  Imports all the types from another module defined by `Trogon.TypeProvider`.

  ## Example

      defmodule UserTypeProvider do
        use Trogon.TypeProvider
        # ...
      end

      defmodule MyAppTypeProvider do
        use Trogon.TypeProvider

        import_type_provider UserTypeProvider
      end
  """
  @spec import_type_provider(provider_mod :: module()) :: Macro.t()
  defmacro import_type_provider(provider_mod) do
    quote bind_quoted: [provider_mod: provider_mod] do
      TypeProvider.__import_type_provider__(
        __MODULE__,
        provider_mod
      )
    end
  end

  # Macro compilation hooks
  defmacro __before_compile__(_env) do
    quote do
      def __type_mapping__, do: @type_mapping
      unquote(TypeProvider.__add_type_conversion_funcs__())
      unquote(TypeProvider.__add_to_type_funcs__())
    end
  end

  # Quote-generating functions for macro expansion
  def __add_to_type_funcs__() do
    quote unquote: false do
      @spec to_type(struct()) :: {:ok, String.t()} | {:error, term()}
      for {_, type, struct_mod} <- @type_mapping do
        def to_type(%unquote(struct_mod){}) do
          {:ok, unquote(type)}
        end
      end

      def to_type(struct) do
        {:error,
         %UnregisteredMappingError{
           mapping: inspect(struct),
           type_provider: __MODULE__
         }}
      end
    end
  end

  def __add_type_conversion_funcs__() do
    quote unquote: false do
      @spec to_module(String.t()) :: {:ok, module()} | {:error, term()}
      for {_, type, struct_mod} <- @type_mapping do
        def to_module(unquote(type)) do
          {:ok, unquote(struct_mod)}
        end
      end

      def to_module(type) do
        {:error, %UnregisteredMappingError{mapping: type, type_provider: __MODULE__}}
      end
    end
  end

  def __register_type__(mod, original_type, struct_mod) do
    ensure_compiled!(mod)

    type = type_with_prefix(mod, original_type)

    if not defines_struct?(struct_mod) do
      raise ArgumentError, """
      Invalid struct registration for type #{inspect(type)}

      Expected: #{inspect(struct_mod)} to implement a struct
      Problem: Module does not define a struct

      To fix this, ensure your module defines a struct:

          defmodule #{inspect(struct_mod)} do
            defstruct [:field1, :field2]
          end
      """
    end

    add_mapping_or_raise!(mod, type, struct_mod)
  end

  def __import_type_provider__(mod, provider_mod) do
    ensure_compiled!(mod)
    ensure_compiled!(provider_mod)

    if not type_provider?(provider_mod) do
      raise ArgumentError, """
      Invalid TypeProvider import in #{inspect(mod)}

      Expected: #{inspect(provider_mod)} to be a valid TypeProvider
      Problem: Module does not use Trogon.TypeProvider

      To fix this, ensure the module you're importing uses TypeProvider:

          defmodule #{inspect(provider_mod)} do
            use Trogon.TypeProvider
            register_type "example", ExampleStruct
          end
      """
    end

    for {_, type, struct_mod} <- provider_mod.__type_mapping__() do
      add_mapping_or_raise!(mod, type, struct_mod, import_from: provider_mod)
    end
  end

  def __register_protobuf_message__(mod, struct_mod) do
    ensure_compiled!(mod)
    ensure_compiled!(struct_mod)

    if not protobuf_message?(struct_mod) do
      raise ArgumentError, """
      Invalid Protobuf message registration in #{inspect(mod)}

      Expected: #{inspect(struct_mod)} to be a Protobuf message with full_name/0
      Problem: Module is not a valid Protobuf message
      """
    end

    type = type_with_prefix(mod, struct_mod.full_name())
    add_mapping_or_raise!(mod, type, struct_mod)
  end

  defp type_with_prefix(mod, type) do
    Module.get_attribute(mod, :type_mapping_prefix) <> type
  end

  defp add_mapping(mod, type, struct_mod) do
    Module.put_attribute(mod, :type_mapping, {mod, type, struct_mod})
  end

  defp add_mapping_or_raise!(mod, type, struct_mod, opts \\ []) do
    case find_mapping_by_type(mod, type) do
      nil ->
        add_mapping(mod, type, struct_mod)

      {_found_mod, _type, found_struct_mod} ->
        raise ArgumentError, duplicate_type_error(mod, type, struct_mod, found_struct_mod, opts)
    end
  end

  defp duplicate_type_error(mod, type, struct_mod, found_struct_mod, opts) do
    case Keyword.get(opts, :import_from) do
      nil ->
        """
        Duplicate type registration for #{inspect(type)}

        Already registered: #{inspect(found_struct_mod)} in #{inspect(mod)}
        Attempted to register: #{inspect(struct_mod)} in #{inspect(mod)}

        Each type must be unique within a TypeProvider.
        Consider using different types or check for duplicate registrations.
        """

      provider_mod ->
        """
        Cannot import type #{inspect(type)} - already exists

        Trying to import from: #{inspect(provider_mod)}
        Into TypeProvider: #{inspect(mod)}

        CONFLICT:
        • Type #{inspect(type)} is already registered as #{inspect(found_struct_mod)}
        • Cannot import #{inspect(struct_mod)} because the type is taken

        SOLUTIONS:
        • Use different types in #{inspect(provider_mod)}
        • Add a prefix to avoid conflicts:
            use Trogon.TypeProvider, prefix: "iam."
        • Import types selectively instead of all at once
        """
    end
  end

  defp find_mapping_by_type(mod, type) do
    mod
    |> Module.get_attribute(:type_mapping)
    |> Enum.find(&mapping?(&1, type))
  end

  defp mapping?({_, current_type, _struct_mod}, type) do
    current_type == type
  end

  defp type_provider?(mod) do
    function_exported?(mod, :__type_mapping__, 0)
  end

  # TODO: Maybe we should refactor to use Protobuf.is_protobuf_message/1 guard once is released?
  # https://github.com/elixir-protobuf/protobuf/pull/428 is merged
  defp protobuf_message?(mod) do
    function_exported?(mod, :full_name, 0) and defines_struct?(mod)
  end

  defp defines_struct?(mod) do
    :functions
    |> mod.__info__()
    |> Keyword.get(:__struct__)
    |> Kernel.!=(nil)
  end

  defp ensure_compiled!(mod) do
    case Code.ensure_compiled(mod) do
      {:error, :nofile} ->
        # Module was compiled inline (e.g., in tests), continue without ensuring compilation
        # We need to find a workaround if somebody requires to fail in this case.
        :ok

      {:error, reason} ->
        raise "could not load module #{inspect(mod)} due to reason #{inspect(reason)}"

      {:module, _} ->
        :ok
    end
  end
end
