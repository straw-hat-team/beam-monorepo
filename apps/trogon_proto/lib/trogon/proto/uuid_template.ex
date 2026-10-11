defmodule Trogon.Proto.Uuid.V1.UuidTemplate do
  @moduledoc """
  Generates deterministic UUIDv5 identities using options from proto definitions.

  Uses compile-time extraction of proto options for fast runtime UUID generation.
  The template is parsed at compile time and generates optimized string concatenation.
  """

  alias TrogonProto.Uuid.V1.Namespace
  alias Uniq.UUID

  @default_trogon_module TrogonProto.Uuid.V1

  @options_schema NimbleOptions.new!(
                    enum: [
                      type: :atom,
                      required: true,
                      doc: "The protobuf enum module containing the identity version definitions."
                    ],
                    version: [
                      type: :atom,
                      required: true,
                      doc: "The identity version atom (e.g., `:IDENTITY_VERSION_V1`)."
                    ]
                  )

  @doc """
  Sets up deterministic UUID generation based on proto definitions.

  ## Proto Definition

  Define your identity versions in a proto file with trogon options:

      syntax = "proto3";

      package acme.order.v1;

      import "trogon/uuid/v1/options.proto";

      message OrderId {
        enum IdentityVersion {
          option (trogon.uuid.v1.enum).namespace = {dns: "acme.com"};

          IDENTITY_VERSION_UNSPECIFIED = 0;
          IDENTITY_VERSION_V1 = 1 [(trogon.uuid.v1.enum_value).format = {
            template: "order/{customer_id}/{order_number}"
          }];
        }

        string value = 1;
      }

  ## Usage

      defmodule MyApp.Order.IdentityVersionV1UuidTemplate do
        use Trogon.Proto.Uuid.V1.UuidTemplate,
          enum: Acme.Order.V1.OrderId.IdentityVersion,
          version: :IDENTITY_VERSION_V1
      end

      # Fast runtime call - namespace and template are pre-computed
      MyApp.Order.IdentityVersionV1UuidTemplate.uuid5(%{customer_id: "cust-123", order_number: "ORD-456"})

  ## Template Syntax

  The template string uses `{name}` placeholders for value interpolation:

      "order/{customer_id}/{order_number}"

  Expects a map with `:customer_id` and `:order_number` keys. Placeholders are
  parsed at compile time and generate optimized string concatenation code.

  ## Multiple Identity Versions

  When your proto defines multiple identity versions, create separate modules:

      # V1 identity
      defmodule MyApp.Order.IdentityVersionV1UuidTemplate do
        use Trogon.Proto.Uuid.V1.UuidTemplate,
          enum: Acme.Order.V1.OrderId.IdentityVersion,
          version: :IDENTITY_VERSION_V1
      end

      # V2 identity
      defmodule MyApp.Order.IdentityVersionV2UuidTemplate do
        use Trogon.Proto.Uuid.V1.UuidTemplate,
          enum: Acme.Order.V1.OrderId.IdentityVersion,
          version: :IDENTITY_VERSION_V2
      end

  ## Options

  #{NimbleOptions.docs(@options_schema)}
  """
  defmacro __using__(opts) do
    validated_opts =
      opts
      |> Keyword.update(:enum, nil, &Macro.expand(&1, __CALLER__))
      |> NimbleOptions.validate!(@options_schema)

    enum_module = Keyword.fetch!(validated_opts, :enum)
    version = Keyword.fetch!(validated_opts, :version)

    {namespace, template} = extract_options(enum_module, version)
    version_namespace = UUID.uuid5(namespace, Atom.to_string(version), :raw)
    template_keys = extract_template_keys(template)

    if template_keys == [] do
      generate_static_uuid_module(version_namespace, template)
    else
      generate_dynamic_uuid_module(version_namespace, template, template_keys)
    end
  end

  defp generate_static_uuid_module(version_namespace, template) do
    name_ast = build_name_ast(parse_template(template))
    template_type_ast = generate_template_type_ast(template)

    quote do
      unquote(template_type_ast)

      @doc """
      Generates a deterministic UUIDv5 (singleton).

      This template has no placeholders, so it always returns the same UUID.
      See `t:template/0` for the template format.
      """
      @spec uuid5() :: String.t()
      def uuid5 do
        Uniq.UUID.uuid5(unquote(version_namespace), unquote(name_ast))
      end
    end
  end

  defp generate_dynamic_uuid_module(version_namespace, template, template_keys) do
    values_typespec = generate_values_typespec(template_keys)
    name_ast = build_name_ast(parse_template(template))
    template_type_ast = generate_template_type_ast(template)

    quote do
      unquote(template_type_ast)

      @typedoc "The map of values required to generate the UUID. See `t:template/0`."
      @type values :: unquote(values_typespec)

      @doc """
      Generates a UUIDv5 using pre-computed namespace and template.

      ## Example

          #{inspect(__MODULE__)}.uuid5(%{customer_id: "cust-123", order_number: "ORD-456"})
          #=> "a1b2c3d4-e5f6-5789-abcd-ef0123456789"
      """
      @spec uuid5(values()) :: String.t()
      def uuid5(values) do
        name = unquote(name_ast)
        Uniq.UUID.uuid5(unquote(version_namespace), name)
      end
    end
  end

  defp generate_template_type_ast(template) do
    quote do
      @typedoc "The template used for UUID generation: `#{unquote(template)}`"
      @type template :: String.t()
    end
  end

  @doc false
  def generate_values_typespec(keys) when is_list(keys) do
    key_types = for key <- keys, do: {key, quote(do: String.Chars.t())}
    {:%{}, [], key_types}
  end

  @doc false
  def extract_template_keys(template) do
    for {:key, key} <- parse_template(template), do: key
  end

  @doc false
  def parse_template(template) do
    # Split template into literal strings and placeholders
    # Example: "order/{customer_id}/{order_number}" becomes:
    #   [{:string, "order/"}, {:key, :customer_id}, {:string, "/"}, {:key, :order_number}]
    template
    |> String.split(~r/\{(\w+)\}/, include_captures: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_part/1)
  end

  defp parse_part(part) do
    case Regex.run(~r/\{(\w+)\}/, part) do
      [_, key] -> {:key, String.to_atom(key)}
      nil -> {:string, part}
    end
  end

  @doc false
  def build_name_ast([]), do: ""

  def build_name_ast(parts) do
    Enum.reduce(parts, nil, fn part, acc ->
      ast = part_to_ast(part)
      if acc, do: quote(do: unquote(acc) <> unquote(ast)), else: ast
    end)
  end

  defp part_to_ast({:string, str}), do: str
  defp part_to_ast({:key, key}), do: quote(do: to_string(Map.fetch!(values, unquote(key))))

  @doc false
  @spec extract_options(module(), atom()) :: {binary(), String.t()}
  def extract_options(enum_module, version) do
    desc = enum_module.descriptor()
    enum_namespace = get_enum_namespace(desc.options)
    {value_namespace, template} = get_value_options(desc.value, version)

    # Resolution order: value-level > enum-level
    namespace = resolve_namespace(value_namespace, enum_namespace)

    {namespace, template}
  end

  defp resolve_namespace(value_namespace, _enum_namespace) when not is_nil(value_namespace) do
    to_uuid(value_namespace)
  end

  defp resolve_namespace(_value_namespace, enum_namespace) when not is_nil(enum_namespace) do
    to_uuid(enum_namespace)
  end

  defp resolve_namespace(nil, nil) do
    raise ArgumentError,
          "No namespace found. Set namespace on either the enum value's format " <>
            "or the enum options using (trogon.uuid.v1.enum).namespace"
  end

  defp get_enum_namespace(nil), do: nil

  defp get_enum_namespace(%{__unknown_fields__: fields}) do
    enum_options_module = Module.concat(@default_trogon_module, EnumOptions)

    case find_field(fields, 870_001) do
      nil -> nil
      binary -> enum_options_module.decode(binary).namespace
    end
  end

  defp get_value_options(values, version) do
    version_name = Atom.to_string(version)
    value_desc = Enum.find(values, &(&1.name == version_name))
    enum_value_options_module = Module.concat(@default_trogon_module, EnumValueOptions)

    case value_desc do
      nil ->
        available_versions = Enum.map(values, &String.to_atom(&1.name))

        raise ArgumentError,
              "Identity version #{inspect(version)} not found. " <>
                "Available versions: #{inspect(available_versions)}"

      %{options: nil} ->
        raise ArgumentError, "No options found for #{inspect(version)}"

      %{options: %{__unknown_fields__: fields}} ->
        case find_field(fields, 870_002) do
          nil ->
            raise ArgumentError, "No format option found for #{inspect(version)}"

          binary ->
            %{format: format} = enum_value_options_module.decode(binary)
            {format.namespace, format.template}
        end
    end
  end

  defp find_field(fields, tag) do
    case Enum.find(fields, &(elem(&1, 0) == tag)) do
      {_, _, binary} -> binary
      nil -> nil
    end
  end

  defp to_uuid(%Namespace{value: {:dns, domain}}), do: UUID.uuid5(:dns, domain, :raw)
  defp to_uuid(%Namespace{value: {:url, url}}), do: UUID.uuid5(:url, url, :raw)
  defp to_uuid(%Namespace{value: {:uuid, uuid_string}}), do: UUID.string_to_binary!(uuid_string)

  defp to_uuid(%Namespace{value: nil}) do
    raise ArgumentError, "Namespace value is not set. The namespace oneof must specify :dns, :url, or :uuid"
  end

  defp to_uuid(%Namespace{value: {type, _}}) do
    raise ArgumentError, "Unknown namespace type: #{inspect(type)}. Expected :dns, :url, or :uuid"
  end

  defp to_uuid(other) do
    raise ArgumentError, "Expected a %Namespace{} struct, got: #{inspect(other)}"
  end
end
