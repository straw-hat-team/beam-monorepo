defmodule Trogon.TypeProvider do
  @moduledoc """
  Provides a type mapping system for converting between string type names and Elixir struct modules.
  """

  alias Trogon.TypeProvider
  alias Trogon.TypeProvider.UnregisteredMappingError

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import TypeProvider, only: [register_type: 2, import_type_provider: 1]

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
    type = type_with_prefix(mod, original_type)

    unless defines_struct?(struct_mod) do
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

    case find_mapping_by_type(mod, type) do
      nil ->
        add_mapping(mod, type, struct_mod)

      {found_mod, type, found_struct_mod} ->
        raise ArgumentError, """
        Duplicate type registration for #{inspect(type)}

        Already registered: #{inspect(found_struct_mod)} in #{inspect(found_mod)}
        Attempted to register: #{inspect(struct_mod)} in #{inspect(mod)}

        Each type must be unique within a TypeProvider.
        Consider using different types or check for duplicate registrations.
        """
    end
  end

  def __import_type_provider__(mod, provider_mod) do
    unless type_provider?(provider_mod) do
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
      case find_mapping_by_type(mod, type) do
        nil ->
          add_mapping(mod, type, struct_mod)

        {_registered_mod, _, found_struct_mod} ->
          raise ArgumentError, """
          Cannot import type "#{type}" - already exists

          Trying to import from: #{inspect(provider_mod)}
          Into TypeProvider: #{inspect(mod)}

          CONFLICT:
          • Type "#{type}" is already registered as #{inspect(found_struct_mod)}
          • Cannot import #{inspect(struct_mod)} because the type is taken

          SOLUTIONS:
          • Use different types in #{inspect(provider_mod)}
          • Add a prefix to avoid conflicts:
              use Trogon.TypeProvider, prefix: "iam."
          • Import types selectively instead of all at once
          """
      end
    end
  end

  defp type_with_prefix(mod, type) do
    Module.get_attribute(mod, :type_mapping_prefix) <> type
  end

  defp add_mapping(mod, type, struct_mod) do
    Module.put_attribute(mod, :type_mapping, {mod, type, struct_mod})
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
    Code.ensure_loaded?(mod) and function_exported?(mod, :__type_mapping__, 0)
  end

  defp defines_struct?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :__struct__, 0)
  end
end
