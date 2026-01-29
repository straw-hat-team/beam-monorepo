defmodule Trogon.Proto.Env do
  @moduledoc """
  Compile-time macro for generating environment variable loaders from proto definitions.

  Reads field-level `trogon_proto.env.v1_alpha1.field` extensions to generate:
  - Typed struct with proper field definitions
  - `load!/0` function that reads from System.get_env()
  - Inspect implementation that masks secret fields automatically

  ## Usage

  Define your configuration message in a proto file with env var options:

      syntax = "proto3";

      package myapp.config.v1;

      import "trogon/env/v1alpha1/options.proto";

      message AppConfig {
        string database_url = 1 [(trogon.env.v1alpha1.field).env_var = {
          visibility: VISIBILITY_SECRET
        }];

        string port = 2 [(trogon.env.v1alpha1.field).env_var = {
          visibility: VISIBILITY_PLAINTEXT,
          default_value: "5432"
        }];
      }

  Then use the macro in a module:

      defmodule MyApp.Config do
        use Trogon.Proto.Env, message: Myapp.Config.V1.AppConfig
      end

  At runtime, load the configuration:

      # Requires DATABASE_URL env var, uses PORT default of 5432
      config = MyApp.Config.load!()

      # Secrets are automatically masked when inspecting/logging
      Logger.info(inspect(config))
  """

  @default_options_module TrogonProto.Env.V1Alpha1
  @extension_tag 870_003
  @system_adapter Application.compile_env(:trogon_proto, :system_adapter,
                                          Trogon.Proto.SystemAdapter.Default)

  defmacro __using__(opts) do
    message_module =
      opts
      |> Keyword.fetch!(:message)
      |> Macro.expand(__CALLER__)

    field_configs = extract_field_options(message_module)

    quote do
      unquote(generate_struct_definition(field_configs))
      unquote(generate_load_function(field_configs))
      unquote(generate_inspect_implementation(field_configs))
    end
  end

  defp extract_field_options(message_module) do
    desc = message_module.descriptor()
    field_options_module = Module.concat(@default_options_module, FieldOptions)
    visibility_module = Module.concat(@default_options_module, Visibility)

    for field_desc <- desc.field do
      field_name = String.to_atom(field_desc.name)

      case get_field_extension(field_desc.options, @extension_tag) do
        nil ->
          nil

        binary ->
          %{env_var: env_var_option} = field_options_module.decode(binary)
          is_repeated = field_desc.label == :LABEL_REPEATED
          has_split_delimiter = env_var_option.split_delimiter && env_var_option.split_delimiter != ""

          if supported_field_type?(field_desc.type) &&
               (not is_repeated || has_split_delimiter) do
            visibility =
              case env_var_option.visibility do
                atom when is_atom(atom) -> visibility_module.value(atom)
                int when is_integer(int) -> int
                nil -> 0
              end

            {field_name,
             %{
               env_var_name: field_name_to_env_var(field_name),
               visibility: visibility,
               default_value: env_var_option.default_value || "",
               field_type: field_desc.type,
               is_repeated: is_repeated,
               split_delimiter: env_var_option.split_delimiter,
               trim: env_var_option.trim
             }}
          else
            label_str =
              case field_desc.label do
                :LABEL_REPEATED -> "repeated "
                :LABEL_REQUIRED -> "required "
                _ -> ""
              end

            IO.warn(
              "Field #{field_desc.name} has env_var extension but unsupported type #{label_str}#{inspect(field_desc.type)}. " <>
                "Only scalar string, int32, int64, float, double, and bool fields are supported" <>
                if is_repeated do
                  " (repeated fields require split_delimiter)"
                else
                  ""
                end <> ".",
              []
            )

            nil
          end
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp supported_field_type?(type) do
    is_supported_scalar_type?(type)
  end

  defp is_supported_scalar_type?(type) when is_atom(type) do
    type in [
      :TYPE_STRING,
      :TYPE_INT32,
      :TYPE_INT64,
      :TYPE_FLOAT,
      :TYPE_DOUBLE,
      :TYPE_BOOL
    ]
  end

  defp is_supported_scalar_type?(type) when is_integer(type) do
    type in [
      # TYPE_STRING
      9,
      # TYPE_INT32
      5,
      # TYPE_INT64
      3,
      # TYPE_FLOAT
      2,
      # TYPE_DOUBLE
      1,
      # TYPE_BOOL
      8
    ]
  end

  defp is_supported_scalar_type?(_), do: false

  defp get_field_extension(nil, _tag), do: nil

  defp get_field_extension(%{__unknown_fields__: fields}, tag) do
    case Enum.find(fields, &(elem(&1, 0) == tag)) do
      {_, _, binary} -> binary
      nil -> nil
    end
  end

  defp field_name_to_env_var(field_name) do
    field_name
    |> Atom.to_string()
    |> String.upcase()
  end

  defp generate_struct_definition(field_configs) do
    struct_fields = for {field_name, _config} <- field_configs, do: {field_name, nil}

    quote do
      defstruct unquote(struct_fields)

      @type t :: %__MODULE__{
              unquote_splicing(
                for {field_name, config} <- field_configs do
                  field_type = generate_type_spec(config.field_type, config.is_repeated)

                  quote do: {unquote(field_name), unquote(field_type)}
                end
              )
            }
    end
  end

  defp generate_type_spec(field_type, is_repeated) do
    base_type =
      case normalize_type(field_type) do
        :string -> quote(do: String.t())
        :int32 -> quote(do: integer())
        :int64 -> quote(do: integer())
        :float -> quote(do: float())
        :double -> quote(do: float())
        :bool -> quote(do: boolean())
        _ -> quote(do: term())
      end

    if is_repeated do
      quote do: [unquote(base_type)]
    else
      base_type
    end
  end

  defp generate_load_function(field_configs) do
    system_adapter = @system_adapter

    field_loaders =
      for {field_name, config} <- field_configs do
        env_var_name = config.env_var_name
        default = config.default_value
        field_type = config.field_type
        is_repeated = config.is_repeated
        split_delimiter = config.split_delimiter
        trim = config.trim

        raw_value =
          if default == "" do
            quote do
              unquote(system_adapter).get_env(unquote(env_var_name)) ||
                raise(
                  ArgumentError,
                  "Required environment variable #{unquote(env_var_name)} is not set"
                )
            end
          else
            quote do
              unquote(system_adapter).get_env(unquote(env_var_name), unquote(default))
            end
          end

        converted_value =
          generate_type_conversion(field_type, raw_value, is_repeated, split_delimiter, trim)

        quote do
          {unquote(field_name), unquote(converted_value)}
        end
      end

    quote do
      @doc """
      Loads environment variables and returns a populated struct.

      Raises ArgumentError if required fields are missing.
      """
      @spec load!() :: t()
      def load! do
        struct!(__MODULE__, [unquote_splicing(field_loaders)])
      end
    end
  end

  defp generate_type_conversion(field_type, raw_value_ast, is_repeated, split_delimiter, trim) do
    scalar_conversion = fn normalized_type ->
      case normalized_type do
        :string ->
          quote do: value

        :int32 ->
          quote do: String.to_integer(value)

        :int64 ->
          quote do: String.to_integer(value)

        :float ->
          quote do: String.to_float(value)

        :double ->
          quote do: String.to_float(value)

        :bool ->
          quote do: String.downcase(value) in ["true", "1", "yes", "on"]

        _ ->
          quote do: value
      end
    end

    normalized = normalize_type(field_type)

    if is_repeated && split_delimiter != "" do
      # Handle repeated field with split and optional trim
      trim_ast =
        if trim == nil do
          # No trim, just use raw value
          quote do: value
        else
          # Generate trim code based on trim specification (oneof field)
          case trim.spec do
            {:unicode_whitespace, _} ->
              # Trim unicode whitespace (default String.trim behavior)
              quote do: String.trim(value)

            {:chars, chars} ->
              # Trim specific characters
              quote do: String.trim(value, unquote(chars))

            nil ->
              # No spec set, don't trim
              quote do: value
          end
        end

      value_map_ast =
        quote do
          String.split(unquote(raw_value_ast), unquote(split_delimiter))
          |> Enum.map(fn value ->
            value = unquote(trim_ast)
            unquote(scalar_conversion.(normalized))
          end)
        end

      value_map_ast
    else
      # Non-repeated field, single value conversion
      case normalized do
        :string ->
          raw_value_ast

        :int32 ->
          quote do
            String.to_integer(unquote(raw_value_ast))
          end

        :int64 ->
          quote do
            String.to_integer(unquote(raw_value_ast))
          end

        :float ->
          quote do
            String.to_float(unquote(raw_value_ast))
          end

        :double ->
          quote do
            String.to_float(unquote(raw_value_ast))
          end

        :bool ->
          quote do
            String.downcase(unquote(raw_value_ast)) in ["true", "1", "yes", "on"]
          end

        _ ->
          raw_value_ast
      end
    end
  end

  defp normalize_type(type) when is_atom(type) do
    case type do
      :TYPE_STRING -> :string
      :TYPE_INT32 -> :int32
      :TYPE_INT64 -> :int64
      :TYPE_FLOAT -> :float
      :TYPE_DOUBLE -> :double
      :TYPE_BOOL -> :bool
      _ -> :string
    end
  end

  defp normalize_type(type) when is_integer(type) do
    case type do
      # TYPE_STRING
      9 -> :string
      # TYPE_INT32
      5 -> :int32
      # TYPE_INT64
      3 -> :int64
      # TYPE_FLOAT
      2 -> :float
      # TYPE_DOUBLE
      1 -> :double
      # TYPE_BOOL
      8 -> :bool
      _ -> :string
    end
  end

  defp normalize_type(_), do: :string

  defp generate_inspect_implementation(field_configs) do
    secret_fields =
      for {name, %{visibility: 2}} <- field_configs do
        name
      end

    field_lines =
      for {field_name, _config} <- field_configs do
        if field_name in secret_fields do
          quote do
            unquote(Atom.to_string(field_name)) <> ": \"***SECRET***\""
          end
        else
          quote do
            unquote(Atom.to_string(field_name)) <>
              ": " <>
              inspect(Map.fetch!(map, unquote(field_name)))
          end
        end
      end

    quote do
      defimpl Inspect do
        def inspect(config, _opts) do
          map = Map.from_struct(config)

          inner =
            [unquote_splicing(field_lines)]
            |> Enum.join(", ")

          "#Trogon.Proto.Env<" <> inner <> ">"
        end
      end
    end
  end
end
