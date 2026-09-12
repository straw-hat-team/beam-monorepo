defmodule Trogon.Proto.Env do
  @moduledoc """
  Compile-time macro for generating environment variable loaders from proto definitions.

  Reads field-level `trogon_proto.env.v1_alpha1.field` extensions to generate:
  - Typed struct with proper field definitions
  - `from_env/0` function that returns `{:ok, t()} | {:error, LoadError.t()}`
  - `from_env!/0` function that returns the struct or raises `LoadError`
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

      # Or handle failures without rescuing (CLI / Mix tasks / health checks):
      case MyApp.Config.from_env() do
        {:ok, config} -> config
        {:error, %Trogon.Proto.Env.LoadError{errors: errors}} -> handle(errors)
      end

      # Secrets are automatically masked when inspecting/logging
      Logger.info(inspect(config))

  ## Steps

  A field may declare an ordered `steps` pipeline. Loading a value is then:

  1. Read the environment variable, or `default_value` when it is absent.
  2. Run each step in order.
  3. Cast the result to the field type.

  `split` is the only step that changes how many values are in play. Steps
  before it see the whole environment value, steps after it run once per
  element. A non-repeated field has no `split`, so every step sees the single
  value.

  - `split` - Breaks the value into elements on a delimiter. Repeated fields only.
  - `trim` - Strips unicode whitespace, or a given set of characters.
  - `decode` - Reads the text as bytes, choosing among `any_of` candidates
    (`base64`, `hex`, `utf8`) by which one satisfies `accept`.
  - `require` - Validates without producing a new value.

  A 32 byte key supplied either base64 encoded or as raw bytes, tolerant of the
  trailing newline that `$(cat key.b64)` leaves behind:

      bytes token_signing_key = 1 [(trogon.env.v1alpha1.field).env_var = {
        visibility: VISIBILITY_SECRET
        steps: [
          {trim: {unicode_whitespace: {}}},
          {decode: {
            any_of: [
              {base64: {alphabet: ALPHABET_STANDARD, padding: PADDING_REQUIRED}},
              {utf8: {}}
            ]
            accept: {byte_size: {exact: 32}}
          }}
        ]
      }];

  The declared size is what decides which reading of the input is correct, so it
  is stated once rather than repeated in a following `require` step.

  Failure messages name the field, the variable, the candidates attempted and
  the observed byte size. They never carry the value itself.

  ## Type Conversions

  Environment variables are always strings. This module converts them to the
  appropriate Elixir types based on the proto field type:

  - `string` - No conversion
  - `bytes` - No conversion; pair with a `decode` step to accept encoded input
  - `int32`, `int64` - Parsed via `String.to_integer/1`
  - `float`, `double` - Parsed via `Float.parse/1` (accepts both "1.5" and "1")
  - `bool` - Case-insensitive, truthy values: `"true"`, `"1"`, `"yes"`, `"on"`;
    all other values are considered `false`
  - `enum` - Exact enum name match (for example `"LOG_LEVEL_DEBUG"`)
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

  @type constraint ::
          {:byte_size, {:exact, non_neg_integer()}}
          | {:byte_size, {:range, non_neg_integer() | nil, non_neg_integer() | nil}}

  @type decode_candidate ::
          {:base64, :standard | :url_safe, :required | :absent}
          | :hex
          | :utf8

  @type step ::
          {:split, String.t()}
          | {:trim, :unicode_whitespace}
          | {:trim, {:chars, String.t()}}
          | {:decode, [decode_candidate()], constraint() | nil}
          | {:require, constraint()}

  @type field_config :: %{
          env_var_name: String.t(),
          visibility: non_neg_integer(),
          default_value: String.t() | nil,
          field_type: atom() | {:enum, module()},
          is_repeated: boolean(),
          steps: [step()]
        }

  @doc false
  # Dialyzer cannot verify the contract when macro-generated call sites pass a map literal
  # mixing scalar field_types (atoms like :string) with enum tuples ({:enum, Module}) in the
  # same field position across entries. Its map-type unification loses precision and flags the
  # call as "will not succeed" even though the union is correct at runtime.
  @dialyzer {:no_contracts, build_field_data: 1}
  @spec build_field_data(%{atom() => field_config()}) ::
          {:ok, [{atom(), any()}]} | {:error, [Trogon.Proto.Env.LoadError.error()]}
  def build_field_data(field_configs) do
    {values, errors} =
      field_configs
      |> Enum.map(&load_field/1)
      |> Enum.split_with(&is_tuple/1)

    case errors do
      [] -> {:ok, values}
      _ -> {:error, errors}
    end
  end

  defp load_field({field_name, config}) do
    case fetch_raw_value(config) do
      {:ok, raw_value} ->
        try_convert(field_name, raw_value, config)

      {:error, :missing} ->
        %{env_var: config.env_var_name, field: field_name, reason: :missing}
    end
  end

  defp try_convert(field_name, raw_value, config) do
    {field_name, convert_field(raw_value, config)}
  rescue
    e in ArgumentError ->
      %{env_var: config.env_var_name, field: field_name, reason: {:invalid, Exception.message(e)}}
  end

  defp fetch_raw_value(%{default_value: nil} = config) do
    case get_env(config.env_var_name) do
      nil -> {:error, :missing}
      value -> {:ok, value}
    end
  end

  defp fetch_raw_value(%{default_value: default} = config) do
    {:ok, get_env(config.env_var_name, default)}
  end

  @doc false
  def __from_env__(wrapper_module, message_module, field_configs) do
    case build_field_data(field_configs) do
      {:ok, field_data} ->
        {:ok, struct!(wrapper_module, env: struct!(message_module, field_data))}

      {:error, errors} ->
        {:error, %Trogon.Proto.Env.LoadError{errors: errors}}
    end
  end

  @doc false
  def __from_env__!(wrapper_module, message_module, field_configs) do
    case __from_env__(wrapper_module, message_module, field_configs) do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
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
  def convert_field(value, %{field_type: type, steps: steps}) do
    normalized = normalize_type(type)

    steps
    |> Enum.reduce(value, &apply_step/2)
    |> cast(normalized)
  end

  defp cast(values, type) when is_list(values), do: Enum.map(values, &to_scalar(&1, type))
  defp cast(value, type), do: to_scalar(value, type)

  defp apply_step({:split, delimiter}, value) when is_binary(value) do
    value
    |> String.split(delimiter)
    |> drop_empty()
  end

  defp apply_step({:trim, how}, values) when is_list(values) do
    values
    |> Enum.map(&do_trim(&1, how))
    |> drop_empty()
  end

  defp apply_step({:trim, how}, value), do: do_trim(value, how)

  defp apply_step({:decode, candidates, accept}, values) when is_list(values) do
    Enum.map(values, &do_decode(&1, candidates, accept))
  end

  defp apply_step({:decode, candidates, accept}, value), do: do_decode(value, candidates, accept)

  defp apply_step({:require, constraint}, values) when is_list(values) do
    Enum.map(values, &do_require(&1, constraint))
  end

  defp apply_step({:require, constraint}, value), do: do_require(value, constraint)

  # An element can only become empty by being split out or trimmed down, so
  # those are the only two points that drop empties.
  defp drop_empty(values), do: Enum.reject(values, &(&1 == ""))

  defp do_trim(value, :unicode_whitespace), do: String.trim(value)
  defp do_trim(value, {:chars, chars}), do: String.trim(value, chars)

  defp do_decode(text, candidates, accept) do
    case Enum.find_value(candidates, &accepted_decoding(&1, text, accept)) do
      {:ok, decoded} -> decoded
      nil -> raise ArgumentError, no_acceptable_decoding_reason(candidates, text, accept)
    end
  end

  defp accepted_decoding(candidate, text, accept) do
    with {:ok, decoded} <- decode_candidate(candidate, text),
         :ok <- check_constraint(decoded, accept) do
      {:ok, decoded}
    else
      _ -> nil
    end
  end

  # Base.decode64/2 with padding: false still accepts a padded input, so absent
  # padding has to be enforced before delegating.
  defp decode_candidate({:base64, _alphabet, :absent} = candidate, text) do
    if String.ends_with?(text, "="), do: :error, else: decode_base64(candidate, text)
  end

  defp decode_candidate({:base64, _alphabet, _padding} = candidate, text), do: decode_base64(candidate, text)

  defp decode_candidate(:hex, text), do: Base.decode16(text, case: :mixed)
  defp decode_candidate(:utf8, text), do: {:ok, text}

  defp decode_base64({:base64, :standard, padding}, text) do
    Base.decode64(text, padding: padding == :required)
  end

  defp decode_base64({:base64, :url_safe, padding}, text) do
    Base.url_decode64(text, padding: padding == :required)
  end

  defp check_constraint(_decoded, nil), do: :ok

  defp check_constraint(decoded, {:byte_size, bound}) do
    if satisfies_byte_size?(byte_size(decoded), bound), do: :ok, else: :error
  end

  # Names what was attempted and how big each reading came out. The contract
  # allows the observed byte size but never the value itself.
  defp no_acceptable_decoding_reason(candidates, text, accept) do
    attempted = Enum.map_join(candidates, ", ", &candidate_label/1)

    sizes =
      candidates
      |> Enum.flat_map(fn candidate ->
        case decode_candidate(candidate, text) do
          {:ok, decoded} -> [byte_size(decoded)]
          :error -> []
        end
      end)
      |> Enum.uniq()

    "no acceptable decoding (attempted: #{attempted}" <>
      decoded_sizes_clause(sizes) <> expected_clause(accept) <> ")"
  end

  defp decoded_sizes_clause([]), do: "; nothing decoded"
  defp decoded_sizes_clause(sizes), do: "; decoded byte sizes: #{Enum.join(sizes, ", ")}"

  defp expected_clause(nil), do: ""
  defp expected_clause({:byte_size, bound}), do: "; expected #{describe_byte_size(bound)}"

  defp candidate_label({:base64, alphabet, padding}), do: "base64(#{alphabet}, #{padding})"
  defp candidate_label(:hex), do: "hex"
  defp candidate_label(:utf8), do: "utf8"

  defp do_require(value, {:byte_size, bound}) do
    size = byte_size(value)

    if satisfies_byte_size?(size, bound) do
      value
    else
      raise ArgumentError, "byte size #{size} does not satisfy #{describe_byte_size(bound)}"
    end
  end

  defp satisfies_byte_size?(size, {:exact, exact}), do: size == exact

  defp satisfies_byte_size?(size, {:range, min, max}) do
    (is_nil(min) or size >= min) and (is_nil(max) or size <= max)
  end

  defp describe_byte_size({:exact, exact}), do: "exactly #{exact} bytes"
  defp describe_byte_size({:range, min, nil}), do: "at least #{min} bytes"
  defp describe_byte_size({:range, nil, max}), do: "at most #{max} bytes"
  defp describe_byte_size({:range, min, max}), do: "between #{min} and #{max} bytes"

  defp to_scalar(value, :string), do: value
  defp to_scalar(value, :bytes), do: value
  defp to_scalar(value, :int32), do: parse_int(value, :int32)
  defp to_scalar(value, :int64), do: parse_int(value, :int64)
  defp to_scalar(value, :float), do: parse_float(value)
  defp to_scalar(value, :double), do: parse_float(value)
  defp to_scalar(value, :bool), do: String.downcase(value) in ["true", "1", "yes", "on"]

  defp to_scalar(value, {:enum, enum_module}) do
    case parse_enum_value(value, enum_module) do
      {:ok, enum_value} -> enum_value
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp parse_int(value, type) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> raise ArgumentError, "not a valid #{type}: #{inspect(value)}"
    end
  end

  defp parse_float(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> raise ArgumentError, "not a valid float: #{inspect(value)}"
    end
  end

  defp normalize_type(:TYPE_STRING), do: :string
  defp normalize_type(:TYPE_BYTES), do: :bytes
  defp normalize_type(:TYPE_INT32), do: :int32
  defp normalize_type(:TYPE_INT64), do: :int64
  defp normalize_type(:TYPE_FLOAT), do: :float
  defp normalize_type(:TYPE_DOUBLE), do: :double
  defp normalize_type(:TYPE_BOOL), do: :bool
  defp normalize_type(:string), do: :string
  defp normalize_type(:bytes), do: :bytes
  defp normalize_type(:int32), do: :int32
  defp normalize_type(:int64), do: :int64
  defp normalize_type(:float), do: :float
  defp normalize_type(:double), do: :double
  defp normalize_type(:bool), do: :bool
  defp normalize_type({:enum, enum_module}) when is_atom(enum_module), do: {:enum, enum_module}

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
      Loads environment variables and returns `{:ok, t()}` on success or
      `{:error, Trogon.Proto.Env.LoadError.t()}` listing every missing or
      invalid variable.

      Use this when reporting failures programmatically (CLI / Mix task /
      health check) so you can format the structured error list yourself.
      """
      @spec from_env() :: {:ok, t()} | {:error, Trogon.Proto.Env.LoadError.t()}
      def from_env do
        Trogon.Proto.Env.__from_env__(__MODULE__, unquote(message_module), unquote(Macro.escape(field_configs)))
      end

      @doc """
      Loads environment variables and returns a wrapped protobuf message.

      Raises `Trogon.Proto.Env.LoadError` with the full list of problems when
      any required env var is missing or any value fails to parse.
      """
      @spec from_env!() :: t()
      def from_env! do
        Trogon.Proto.Env.__from_env__!(__MODULE__, unquote(message_module), unquote(Macro.escape(field_configs)))
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
    field_props = message_module.__message_props__().field_props

    desc.field
    |> Enum.map(&extract_field_option(&1, Map.fetch!(field_props, &1.number)))
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp extract_field_option(field_desc, field_prop) do
    case get_field_extension(field_desc.options, @extension_tag) do
      nil -> nil
      binary -> process_env_var_extension(field_desc, field_prop, binary)
    end
  end

  defp process_env_var_extension(field_desc, field_prop, binary) do
    %{env_var: env_var_option} = FieldOptions.decode(binary)
    is_repeated = field_prop.repeated?
    field_type = field_prop.type

    cond do
      is_nil(env_var_option) ->
        raise_field_error!(field_desc.name, "has an env_var extension but env_var is empty")

      valid_env_field?(field_type, is_repeated, env_var_option) ->
        {String.to_atom(field_desc.name), build_field_config(field_desc, field_type, env_var_option, is_repeated)}

      true ->
        raise_field_error!(field_desc.name, unsupported_field_reason(field_desc, field_type, is_repeated))
    end
  end

  defp build_field_config(field_desc, field_type, env_var_option, is_repeated) do
    default_value = env_var_option.default_value
    steps = build_steps!(field_desc.name, field_type, env_var_option, is_repeated)

    config = %{
      env_var_name: field_name_to_env_var(field_desc.name),
      visibility: visibility_value(env_var_option.visibility),
      default_value: default_value,
      field_type: field_type,
      is_repeated: is_repeated,
      steps: steps
    }

    validate_default_value!(field_desc.name, field_type, config)

    config
  end

  defp build_steps!(field_name, field_type, env_var_option, is_repeated) do
    case env_var_option.steps do
      [] ->
        legacy_steps(env_var_option, is_repeated)

      steps ->
        reject_legacy_combination!(field_name, env_var_option)

        steps
        |> Enum.map(&build_step!(field_name, &1))
        |> tap(&validate_pipeline!(field_name, field_type, is_repeated, &1))
    end
  end

  # The deprecated split_delimiter and trim only ever applied to repeated
  # fields, so they translate to a pipeline only in that shape.
  defp legacy_steps(env_var_option, is_repeated) do
    if is_repeated and has_split_delimiter?(env_var_option) do
      [{:split, env_var_option.split_delimiter} | legacy_trim_step(env_var_option.trim)]
    else
      []
    end
  end

  defp legacy_trim_step(nil), do: []
  defp legacy_trim_step(%{by: {:unicode_whitespace, _}}), do: [{:trim, :unicode_whitespace}]
  defp legacy_trim_step(%{by: {:chars, chars}}), do: [{:trim, {:chars, chars}}]
  defp legacy_trim_step(_), do: []

  defp reject_legacy_combination!(field_name, env_var_option) do
    legacy =
      [
        {"split_delimiter", has_split_delimiter?(env_var_option)},
        {"trim", not is_nil(env_var_option.trim)}
      ]
      |> Enum.filter(&elem(&1, 1))
      |> Enum.map(&elem(&1, 0))

    unless legacy == [] do
      raise_field_error!(
        field_name,
        "declares steps together with the deprecated #{Enum.join(legacy, " and ")}; use steps alone"
      )
    end
  end

  defp build_step!(field_name, %{op: {:split, %{delimiter: delimiter}}}) do
    if delimiter in [nil, ""] do
      raise_field_error!(field_name, "has a split step with an empty delimiter")
    end

    {:split, delimiter}
  end

  defp build_step!(_field_name, %{op: {:trim, %{by: {:unicode_whitespace, _}}}}) do
    {:trim, :unicode_whitespace}
  end

  defp build_step!(field_name, %{op: {:trim, %{by: {:chars, chars}}}}) do
    if chars in [nil, ""] do
      raise_field_error!(field_name, "has a trim step with an empty chars set")
    end

    {:trim, {:chars, chars}}
  end

  defp build_step!(field_name, %{op: {:trim, _}}) do
    raise_field_error!(field_name, "has a trim step without a by")
  end

  defp build_step!(field_name, %{op: {:decode, decode}}) do
    candidates = build_candidates!(field_name, decode.any_of)
    accept = build_constraints!(field_name, decode.accept)

    if length(candidates) > 1 and is_nil(accept) do
      raise_field_error!(field_name, "has a decode step with several candidates but no accept")
    end

    {:decode, candidates, accept}
  end

  defp build_step!(field_name, %{op: {:require, constraints}}) do
    case build_constraints!(field_name, constraints) do
      nil -> raise_field_error!(field_name, "has an empty require step")
      constraint -> {:require, constraint}
    end
  end

  defp build_step!(field_name, _step) do
    raise_field_error!(field_name, "has a step without an op")
  end

  defp build_candidates!(field_name, []) do
    raise_field_error!(field_name, "has a decode step with no any_of candidates")
  end

  defp build_candidates!(field_name, any_of) do
    candidates = Enum.map(any_of, &build_candidate!(field_name, &1))

    kinds = Enum.map(candidates, &candidate_kind/1)

    if length(Enum.uniq(kinds)) != length(kinds) do
      raise_field_error!(field_name, "has a decode step with repeated candidates")
    end

    if :utf8 in kinds and List.last(kinds) != :utf8 do
      raise_field_error!(field_name, "has a decode step where utf8 is not the last candidate")
    end

    candidates
  end

  defp build_candidate!(field_name, %{as: {:base64, base64}}) do
    {:base64, base64_alphabet!(field_name, base64.alphabet), base64_padding!(field_name, base64.padding)}
  end

  defp build_candidate!(_field_name, %{as: {:hex, _}}), do: :hex
  defp build_candidate!(_field_name, %{as: {:utf8, _}}), do: :utf8

  defp build_candidate!(field_name, _candidate) do
    raise_field_error!(field_name, "has a decode candidate without an as")
  end

  defp candidate_kind({:base64, _alphabet, _padding}), do: :base64
  defp candidate_kind(kind), do: kind

  defp base64_alphabet!(_field_name, :ALPHABET_STANDARD), do: :standard
  defp base64_alphabet!(_field_name, :ALPHABET_URL_SAFE), do: :url_safe

  defp base64_alphabet!(field_name, alphabet) do
    raise_field_error!(field_name, "has a base64 candidate with an undeclared alphabet #{inspect(alphabet)}")
  end

  defp base64_padding!(_field_name, :PADDING_REQUIRED), do: :required
  defp base64_padding!(_field_name, :PADDING_ABSENT), do: :absent

  defp base64_padding!(field_name, padding) do
    raise_field_error!(field_name, "has a base64 candidate with an undeclared padding #{inspect(padding)}")
  end

  defp build_constraints!(_field_name, nil), do: nil

  defp build_constraints!(field_name, %{byte_size: nil}) do
    raise_field_error!(field_name, "has empty constraints")
  end

  defp build_constraints!(field_name, %{byte_size: byte_size}) do
    {:byte_size, build_byte_size!(field_name, byte_size)}
  end

  defp build_byte_size!(_field_name, %{bound: {:exact, exact}}), do: {:exact, exact}

  defp build_byte_size!(field_name, %{bound: {:range, %{min: nil, max: nil}}}) do
    raise_field_error!(field_name, "has a byte_size range without a bound")
  end

  defp build_byte_size!(field_name, %{bound: {:range, %{min: min, max: max}}}) do
    if not is_nil(min) and not is_nil(max) and min > max do
      raise_field_error!(field_name, "has a byte_size range with min #{min} above max #{max}")
    end

    {:range, min, max}
  end

  defp build_byte_size!(field_name, _byte_size) do
    raise_field_error!(field_name, "has a byte_size without a bound")
  end

  defp validate_pipeline!(field_name, field_type, is_repeated, steps) do
    validate_split_placement!(field_name, is_repeated, steps)
    validate_decode_placement!(field_name, field_type, steps)
    validate_constraint_types!(field_name, field_type, steps)
  end

  defp validate_split_placement!(field_name, is_repeated, steps) do
    case Enum.split_while(steps, &(not match?({:split, _}, &1))) do
      {_before, []} ->
        :ok

      {[], [_split | rest]} ->
        unless is_repeated do
          raise_field_error!(field_name, "has a split step but is not repeated")
        end

        if Enum.any?(rest, &match?({:split, _}, &1)) do
          raise_field_error!(field_name, "has more than one split step")
        end

      {_before, _} ->
        raise_field_error!(field_name, "has a split step that is not first")
    end
  end

  defp validate_decode_placement!(field_name, field_type, steps) do
    decodes = Enum.count(steps, &match?({:decode, _, _}, &1))

    cond do
      decodes == 0 ->
        :ok

      decodes > 1 ->
        raise_field_error!(field_name, "has more than one decode step")

      not decodable_type?(field_type) ->
        raise_field_error!(field_name, "has a decode step but type #{inspect(field_type)} is not bytes or string")

      true ->
        validate_trims_before_decode!(field_name, steps)
    end
  end

  defp validate_trims_before_decode!(field_name, steps) do
    {_before, [_decode | rest]} = Enum.split_while(steps, &(not match?({:decode, _, _}, &1)))

    if Enum.any?(rest, &match?({:trim, _}, &1)) do
      raise_field_error!(field_name, "has a trim step after its decode step")
    end
  end

  defp validate_constraint_types!(field_name, field_type, steps) do
    constrains_bytes? =
      Enum.any?(steps, fn
        {:require, {:byte_size, _}} -> true
        {:decode, _candidates, {:byte_size, _}} -> true
        _ -> false
      end)

    if constrains_bytes? and not decodable_type?(field_type) do
      raise_field_error!(field_name, "constrains byte_size but type #{inspect(field_type)} is not bytes or string")
    end
  end

  defp decodable_type?(field_type) do
    normalize_type(field_type) in [:bytes, :string]
  end

  defp raise_field_error!(field_name, description) do
    raise CompileError, description: "Field #{field_name} #{description}."
  end

  defp validate_default_value!(_field_name, _field_type, %{default_value: nil}), do: :ok
  defp validate_default_value!(_field_name, _field_type, %{default_value: ""}), do: :ok

  defp validate_default_value!(field_name, field_type, %{steps: [_ | _]} = config) do
    convert_field(config.default_value, config)
    :ok
  rescue
    error in [ArgumentError] ->
      invalid_default!(field_name, field_type, config.default_value, Exception.message(error))
  end

  defp validate_default_value!(field_name, field_type, %{default_value: default_value}) do
    normalized = normalize_type(field_type)

    case validate_parseable(default_value, normalized) do
      :ok -> :ok
      {:error, reason} -> invalid_default!(field_name, field_type, default_value, reason)
    end
  end

  defp invalid_default!(field_name, field_type, default_value, reason) do
    raise CompileError,
      description:
        "Field #{field_name} has invalid default_value #{inspect(default_value)} for type #{inspect(field_type)}: #{reason}"
  end

  defp validate_parseable(_value, :string), do: :ok
  defp validate_parseable(_value, :bytes), do: :ok
  defp validate_parseable(_value, :bool), do: :ok
  defp validate_parseable(value, {:enum, enum_module}), do: validate_enum_value(value, enum_module)

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

  defp validate_enum_value(value, enum_module) do
    case parse_enum_value(value, enum_module) do
      {:ok, _enum_value} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp visibility_value(nil), do: Visibility.value(:VISIBILITY_UNSPECIFIED)
  defp visibility_value(atom) when is_atom(atom), do: Visibility.value(atom)
  defp visibility_value(int) when is_integer(int), do: int

  defp unsupported_field_reason(field_desc, field_type, is_repeated) do
    label_str =
      case field_desc.label do
        :LABEL_REPEATED -> "repeated "
        :LABEL_REQUIRED -> "required "
        _ -> ""
      end

    "has an env_var extension but unsupported type #{label_str}#{inspect(field_type)}; " <>
      "only scalar string, bytes, int32, int64, float, double, bool, and enum fields are supported" <>
      if is_repeated do
        " (repeated fields require a split step)"
      else
        ""
      end
  end

  defp has_split_delimiter?(%{split_delimiter: delimiter}) do
    not is_nil(delimiter) and delimiter != ""
  end

  defp valid_env_field?(field_type, is_repeated, env_var_option) do
    scalar_supported = supported_env_type?(field_type)
    repeated_ok = not is_repeated || splits?(env_var_option)
    scalar_supported && repeated_ok
  end

  defp splits?(env_var_option) do
    has_split_delimiter?(env_var_option) or
      Enum.any?(env_var_option.steps, &match?(%{op: {:split, _}}, &1))
  end

  defp supported_env_type?(:TYPE_STRING), do: true
  defp supported_env_type?(:TYPE_BYTES), do: true
  defp supported_env_type?(:TYPE_INT32), do: true
  defp supported_env_type?(:TYPE_INT64), do: true
  defp supported_env_type?(:TYPE_FLOAT), do: true
  defp supported_env_type?(:TYPE_DOUBLE), do: true
  defp supported_env_type?(:TYPE_BOOL), do: true
  defp supported_env_type?(:string), do: true
  defp supported_env_type?(:bytes), do: true
  defp supported_env_type?(:int32), do: true
  defp supported_env_type?(:int64), do: true
  defp supported_env_type?(:float), do: true
  defp supported_env_type?(:double), do: true
  defp supported_env_type?(:bool), do: true
  defp supported_env_type?({:enum, enum_module}) when is_atom(enum_module), do: true
  defp supported_env_type?(_), do: false

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

  defp parse_enum_value(value, enum_module) when is_binary(value) do
    with {:ok, enum_tag} <- fetch_enum_tag(value, enum_module) do
      {:ok, enum_module.key(enum_tag)}
    end
  end

  defp fetch_enum_tag(value, enum_module) do
    {:ok, enum_module.value(value)}
  rescue
    FunctionClauseError ->
      {:error, invalid_enum_value_reason(value, enum_module)}
  end

  defp invalid_enum_value_reason(value, enum_module) do
    available =
      enum_module
      |> enum_names()
      |> Enum.join(", ")

    "not a valid enum name #{inspect(value)} for #{inspect(enum_module)}. Expected one of: #{available}"
  end

  defp enum_names(enum_module) do
    enum_module
    |> apply(:mapping, [])
    |> Map.keys()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.sort()
  end
end
