defmodule Trogon.Proto.Env do
  @moduledoc """
  Compile-time macro for generating environment variable loaders from proto definitions.

  Reads field-level `trogon_proto.env.v1_alpha1.field` extensions to generate:
  - Typed struct with proper field definitions
  - `from_env!/0` function that reads from System.get_env()
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
      config = MyApp.Config.from_env!()

      # Secrets are automatically masked when inspecting/logging
      Logger.info(inspect(config))

  ## Type Conversions

  Environment variables are always strings. This module converts them to the
  appropriate Elixir types based on the proto field type:

  - `string` - No conversion
  - `int32`, `int64` - Parsed via `String.to_integer/1`
  - `float`, `double` - Parsed via `Float.parse/1` (accepts both "1.5" and "1")
  - `bool` - Case-insensitive, truthy values: `"true"`, `"1"`, `"yes"`, `"on"`;
    all other values are considered `false`
  """

  alias TrogonProto.Env.V1Alpha1.FieldOptions
  alias TrogonProto.Env.V1Alpha1.Visibility

  # Visibility codes - UNSPECIFIED (0) and SECRET (2) are both masked in inspect (secure by default)
  @visibility_plaintext Visibility.value(:VISIBILITY_PLAINTEXT)

  # Proto extension and module configuration
  @extension_tag 870_003
  @system_adapter Application.compile_env(:trogon_proto, [__MODULE__, :system], System)

  defdelegate get_env(name), to: @system_adapter
  defdelegate get_env(name, default), to: @system_adapter
  defdelegate fetch_env!(name), to: @system_adapter

  @type field_config :: %{
          env_var_name: String.t(),
          visibility: non_neg_integer(),
          default_value: String.t(),
          field_type: atom(),
          is_repeated: boolean(),
          split_delimiter: String.t(),
          trim: nil | map()
        }

  # Field conversion helpers
  @doc false
  @spec build_field_data(%{atom() => field_config()}) :: [{atom(), any()}]
  def build_field_data(field_configs) do
    for {field_name, config} <- field_configs do
      raw_value = get_raw_value(config)
      converted = convert_field(raw_value, config)
      {field_name, converted}
    end
  end

  defp get_raw_value(%{default_value: nil} = config) do
    fetch_env!(config.env_var_name)
  end

  defp get_raw_value(%{default_value: default} = config) do
    get_env(config.env_var_name, default)
  end

  @doc false
  def to_inspect(config, field_configs) do
    prefix = "#" <> inspect(config.__struct__) <> "<"

    if config.env do
      msg_map = Map.from_struct(config.env)

      inner = Enum.map_join(field_configs, ", ", &format_field_line(&1, msg_map))

      prefix <> inner <> ">"
    else
      prefix <> "nil>"
    end
  end

  defp format_field_line({field_name, %{visibility: @visibility_plaintext}}, msg_map) do
    "#{field_name}: #{inspect(msg_map[field_name])}"
  end

  defp format_field_line({field_name, %{visibility: _}}, _msg_map) do
    "#{field_name}: \"***SECRET***\""
  end

  @doc false
  def convert_field(value, %{field_type: type, is_repeated: is_repeated, split_delimiter: delimiter, trim: trim}) do
    normalized = normalize_type(type)

    if is_repeated && delimiter != "" do
      value
      |> String.split(delimiter)
      |> Enum.map(&trim(&1, trim))
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&to_scalar(&1, normalized))
    else
      to_scalar(value, normalized)
    end
  end

  defp trim(value, nil), do: value
  defp trim(value, %{by: {:unicode_whitespace, _}}), do: String.trim(value)
  defp trim(value, %{by: {:chars, chars}}), do: String.trim(value, chars)
  defp trim(value, _), do: value

  defp to_scalar(value, :string), do: value
  defp to_scalar(value, :int32), do: String.to_integer(value)
  defp to_scalar(value, :int64), do: String.to_integer(value)
  defp to_scalar(value, :float), do: parse_float(value)
  defp to_scalar(value, :double), do: parse_float(value)
  defp to_scalar(value, :bool), do: String.downcase(value) in ["true", "1", "yes", "on"]

  defp parse_float(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> raise ArgumentError, "not a valid float: #{inspect(value)}"
    end
  end

  defp normalize_type(:TYPE_STRING), do: :string
  defp normalize_type(:TYPE_INT32), do: :int32
  defp normalize_type(:TYPE_INT64), do: :int64
  defp normalize_type(:TYPE_FLOAT), do: :float
  defp normalize_type(:TYPE_DOUBLE), do: :double
  defp normalize_type(:TYPE_BOOL), do: :bool

  @doc """
  Defines an environment variable loader struct from a protobuf message.

  ## Options

  - `:message` (required) - The protobuf message module to extract env vars from
  """
  defmacro __using__(opts) do
    message_module =
      opts
      |> Keyword.fetch!(:message)
      |> Macro.expand(__CALLER__)

    field_configs = extract_field_options(message_module)

    quote location: :keep do
      unquote(__generated_struct_and_type__(field_configs, message_module))
      unquote(__generated_load_function__(field_configs, message_module))
      unquote(__generated_inspect_implementation__(field_configs))
    end
  end

  defp __generated_struct_and_type__(_field_configs, message_module) do
    quote location: :keep do
      @type t :: %__MODULE__{env: unquote(message_module).t()}

      defstruct [:env]
    end
  end

  defp __generated_load_function__(field_configs, message_module) do
    quote location: :keep do
      @doc """
      Loads environment variables and returns a wrapped protobuf message.

      Raises `System.EnvError` when a required env var is missing.
      """
      @spec from_env!() :: t()
      def from_env! do
        field_data = Trogon.Proto.Env.build_field_data(unquote(Macro.escape(field_configs)))
        message = struct!(unquote(message_module), field_data)
        %__MODULE__{env: message}
      end
    end
  end

  defp __generated_inspect_implementation__(field_configs) do
    quote location: :keep do
      defimpl Inspect do
        def inspect(config, _opts) do
          Trogon.Proto.Env.to_inspect(config, unquote(Macro.escape(field_configs)))
        end
      end
    end
  end

  @spec extract_field_options(module()) :: map()
  defp extract_field_options(message_module) do
    desc = message_module.descriptor()

    desc.field
    |> Enum.map(&extract_field_option/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_field_option(field_desc) do
    case get_field_extension(field_desc.options, @extension_tag) do
      nil -> nil
      binary -> process_env_var_extension(field_desc, binary)
    end
  end

  defp process_env_var_extension(field_desc, binary) do
    %{env_var: env_var_option} = FieldOptions.decode(binary)
    is_repeated = field_desc.label == :LABEL_REPEATED

    cond do
      is_nil(env_var_option) ->
        warn_empty_env_var_extension(field_desc)
        nil

      valid_env_field?(field_desc.type, is_repeated, env_var_option) ->
        {String.to_atom(field_desc.name), build_field_config(field_desc, env_var_option, is_repeated)}

      true ->
        warn_unsupported_field(field_desc, is_repeated)
        nil
    end
  end

  defp build_field_config(field_desc, env_var_option, is_repeated) do
    default_value = env_var_option.default_value

    validate_default_value!(field_desc.name, field_desc.type, default_value)

    %{
      env_var_name: field_name_to_env_var(field_desc.name),
      visibility: visibility_value(env_var_option.visibility),
      default_value: default_value,
      field_type: field_desc.type,
      is_repeated: is_repeated,
      split_delimiter: env_var_option.split_delimiter || "",
      trim: env_var_option.trim
    }
  end

  defp validate_default_value!(_field_name, _field_type, nil), do: :ok
  defp validate_default_value!(_field_name, _field_type, ""), do: :ok

  defp validate_default_value!(field_name, field_type, default_value) do
    normalized = normalize_type(field_type)

    case validate_parseable(default_value, normalized) do
      :ok ->
        :ok

      {:error, reason} ->
        raise CompileError,
          description:
            "Field #{field_name} has invalid default_value #{inspect(default_value)} for type #{inspect(field_type)}: #{reason}"
    end
  end

  defp validate_parseable(_value, :string), do: :ok
  defp validate_parseable(_value, :bool), do: :ok

  defp validate_parseable(value, type) when type in [:int32, :int64] do
    case Integer.parse(value) do
      {_int, ""} -> :ok
      {_int, rest} -> {:error, "trailing characters: #{inspect(rest)}"}
      :error -> {:error, "not a valid integer"}
    end
  end

  defp validate_parseable(value, type) when type in [:float, :double] do
    case Float.parse(value) do
      {_float, _} -> :ok
      :error -> {:error, "not a valid float"}
    end
  end

  defp warn_empty_env_var_extension(field_desc) do
    IO.warn(
      "Field #{field_desc.name} has env_var extension but env_var is empty; skipping.",
      []
    )
  end

  defp visibility_value(atom) when is_atom(atom), do: Visibility.value(atom)
  defp visibility_value(int) when is_integer(int), do: int
  defp visibility_value(nil), do: Visibility.value(:VISIBILITY_UNSPECIFIED)

  defp warn_unsupported_field(field_desc, is_repeated) do
    label_str =
      case field_desc.label do
        :LABEL_REPEATED -> "repeated "
        :LABEL_REQUIRED -> "required "
        _ -> ""
      end

    message =
      "Field #{field_desc.name} has env_var extension but unsupported type #{label_str}#{inspect(field_desc.type)}. " <>
        "Only scalar string, int32, int64, float, double, and bool fields are supported" <>
        if is_repeated do
          " (repeated fields require split_delimiter)"
        else
          ""
        end <> "."

    IO.warn(message, [])
  end

  defp has_split_delimiter?(%{split_delimiter: delimiter}) do
    delimiter && delimiter != ""
  end

  defp valid_env_field?(field_type, is_repeated, env_var_option) when not is_nil(env_var_option) do
    scalar_supported = supported_scalar_type?(field_type)
    repeated_ok = not is_repeated || has_split_delimiter?(env_var_option)
    scalar_supported && repeated_ok
  end

  defp valid_env_field?(_, _, _), do: false

  defp supported_scalar_type?(:TYPE_STRING), do: true
  defp supported_scalar_type?(:TYPE_INT32), do: true
  defp supported_scalar_type?(:TYPE_INT64), do: true
  defp supported_scalar_type?(:TYPE_FLOAT), do: true
  defp supported_scalar_type?(:TYPE_DOUBLE), do: true
  defp supported_scalar_type?(:TYPE_BOOL), do: true
  defp supported_scalar_type?(_), do: false

  defp get_field_extension(nil, _tag), do: nil

  defp get_field_extension(%{__unknown_fields__: fields}, tag) do
    case Enum.find(fields, &(elem(&1, 0) == tag)) do
      {_, _, binary} -> binary
      nil -> nil
    end
  end

  defp field_name_to_env_var(field_name) when is_binary(field_name) do
    String.upcase(field_name)
  end
end
