defmodule OnePiece.Commanded.TypeProvider do
  @moduledoc """
  Implements `Commanded.EventStore.TypeProvider` behavior. Using macros to generate the behavior.
  """

  alias OnePiece.Commanded.TypeProvider
  alias OnePiece.Commanded.Helpers

  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      import TypeProvider, only: [register_type: 2, import_type_provider: 1]

      @type_mapping_prefix Keyword.get(opts, :prefix, "")
      @behaviour Commanded.EventStore.TypeProvider
      @before_compile TypeProvider

      Module.register_attribute(__MODULE__, :type_mapping, accumulate: true)
    end
  end

  @doc """
  Registers a mapping from an name string to an Elixir Module that defines a struct.

  ## Example

      defmodule MyTypeProvider do
        use OnePiece.Commanded.TypeProvider,
          prefix: "accounts." # optional, adds the prefix to the type name

        register_type "account_created", AccountCreated
      end
  """
  @spec register_type(name :: String.t(), struct_mod :: module()) :: Macro.t()
  defmacro register_type(name, struct_mod) do
    quote bind_quoted: [name: name, struct_mod: struct_mod] do
      TypeProvider.__register_type__(
        __MODULE__,
        name,
        struct_mod
      )
    end
  end

  @doc """
  Imports all the types from another module defined by `OnePiece.Commanded.TypeProvider.TypeProvider`.

  ## Example

      defmodule UserTypeProvider do
        use OnePiece.Commanded.TypeProvider
        # ...
      end

      defmodule MyAppTypeProvider do
        use OnePiece.Commanded.TypeProvider

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

  defmacro __before_compile__(_env) do
    quote do
      def __type_mapping__, do: @type_mapping
      unquote(TypeProvider.__add_to_struct_funcs__())
      unquote(TypeProvider.__add_to_string_funcs__())
    end
  end

  def __add_to_string_funcs__() do
    quote unquote: false do
      @spec to_string(struct()) :: String.t() | no_return()
      for {_, name, struct_mod} <- @type_mapping do
        def to_string(%unquote(struct_mod){}) do
          unquote(name)
        end
      end

      def to_string(struct) do
        raise ArgumentError,
              "#{inspect(struct)} is not registered in the #{inspect(__MODULE__)} type provider"
      end
    end
  end

  def __add_to_struct_funcs__() do
    quote unquote: false do
      @spec to_struct(String.t()) :: struct() | no_return()
      for {_, name, struct_mod} <- @type_mapping do
        def to_struct(unquote(name)) do
          %unquote(struct_mod){}
        end
      end

      def to_struct(name) do
        raise ArgumentError,
              "#{inspect(name)} is not registered in the #{inspect(__MODULE__)} type provider"
      end
    end
  end

  def __register_type__(mod, original_name, struct_mod) do
    name = name_with_prefix(mod, original_name)

    unless Helpers.defines_struct?(struct_mod) do
      raise ArgumentError,
            "#{inspect(name)} registration expected #{inspect(struct_mod)} to be a module that implements a struct"
    end

    case find_mapping_by_name(mod, name) do
      nil ->
        add_mapping(mod, name, struct_mod)

      {found_mod, name, found_struct_mod} ->
        raise ArgumentError,
              "#{inspect(name)} already registered with #{inspect(found_struct_mod)} in #{inspect(found_mod)}"
    end
  end

  def __import_type_provider__(mod, provider_mod) do
    unless type_provider?(provider_mod) do
      raise ArgumentError,
            "#{inspect(mod)} import expected #{inspect(provider_mod)} module to be a #{inspect(TypeProvider)}"
    end

    for {_, name, struct_mod} <- provider_mod.__type_mapping__() do
      case find_mapping_by_name(mod, name) do
        nil ->
          add_mapping(mod, name, struct_mod)

        {registered_mod, _, found_struct_mod} ->
          raise ArgumentError,
                "failed to import types from #{inspect(provider_mod)} into #{inspect(mod)} because #{inspect(name)} already registered for #{inspect(found_struct_mod)} registered in #{inspect(registered_mod)}"
      end
    end
  end

  defp name_with_prefix(mod, name) do
    Module.get_attribute(mod, :type_mapping_prefix) <> name
  end

  defp add_mapping(mod, name, struct_mod) do
    Module.put_attribute(mod, :type_mapping, {mod, name, struct_mod})
  end

  defp find_mapping_by_name(mod, name) do
    mod
    |> Module.get_attribute(:type_mapping)
    |> Enum.find(&is_mapping?(&1, name))
  end

  defp is_mapping?({_, current_name, _struct_mod}, name) do
    current_name == name
  end

  defp type_provider?(mod) do
    :functions
    |> mod.__info__()
    |> Keyword.get(:__type_mapping__)
    |> Kernel.!=(nil)
  end
end
