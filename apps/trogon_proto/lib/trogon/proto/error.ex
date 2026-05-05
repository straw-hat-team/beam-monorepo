defmodule Trogon.Proto.Error do
  @moduledoc false

  alias TrogonProto.Error.V1Alpha1.Code
  alias TrogonProto.Error.V1Alpha1.FieldOptions
  alias TrogonProto.Error.V1Alpha1.MessageOptions

  @message_extension_tag 870_012
  @field_extension_tag 870_013
  @valid_codes Map.keys(Code.mapping())

  @visibility_mapping %{
    VISIBILITY_INTERNAL: :INTERNAL,
    VISIBILITY_PRIVATE: :PRIVATE,
    VISIBILITY_PUBLIC: :PUBLIC
  }

  @doc false
  @typep value_policy :: {:default, String.t()} | {:fixed, String.t()} | nil

  @spec field_specs(module()) :: [{String.t(), atom(), atom(), value_policy()}]
  def field_specs(message_module) do
    field_options_by_name = descriptor_field_options(message_module)

    for {_tag, props} <- message_module.__message_props__().field_props do
      {visibility, value_policy} = Map.get(field_options_by_name, props.name, {:INTERNAL, nil})
      {props.json_name, props.name_atom, visibility, value_policy}
    end
  end

  defp descriptor_field_options(message_module) do
    Map.new(message_module.descriptor().field, &field_to_options/1)
  end

  defp field_to_options(field) do
    {field.name, read_field_options(field)}
  end

  defp read_field_options(%{options: nil}), do: {:INTERNAL, nil}

  defp read_field_options(%{options: options}) do
    case get_extension(options, @field_extension_tag) do
      nil -> {:INTERNAL, nil}
      binary -> decode_field_options(binary)
    end
  end

  defp decode_field_options(binary) do
    opts = FieldOptions.decode(binary)
    {resolve_visibility(opts.visibility), resolve_value_policy(opts)}
  end

  defp resolve_value_policy(%{value_policy: {:default_value, v}}), do: {:default, v}
  defp resolve_value_policy(%{value_policy: {:value, v}}), do: {:fixed, v}
  defp resolve_value_policy(_), do: nil

  @doc false
  @spec extract_template_opts!(module()) :: keyword()
  def extract_template_opts!(message_module) do
    validate_field_types!(message_module)

    message_module
    |> read_extension!()
    |> to_template_opts()
  end

  defp validate_field_types!(message_module) do
    for field <- message_module.descriptor().field,
        field.type != :TYPE_STRING do
      raise ArgumentError,
            "#{inspect(message_module)} field #{inspect(field.name)} must be of type string, got #{inspect(field.type)}"
    end
  end

  defp read_extension!(message_module) do
    descriptor = message_module.descriptor()

    case get_extension(descriptor.options, @message_extension_tag) do
      nil ->
        raise ArgumentError,
              "#{inspect(message_module)} does not have a trogon.error.v1alpha1.message extension"

      binary ->
        MessageOptions.decode(binary)
    end
  end

  defp to_template_opts(%MessageOptions{template: nil}) do
    raise ArgumentError, "error extension is present but template is missing"
  end

  defp to_template_opts(%MessageOptions{template: template}) do
    [
      domain: require_nonempty!(template.domain, :domain),
      reason: require_nonempty!(template.reason, :reason),
      message: require_nonempty!(template.message, :message),
      code: require_code!(template.code),
      visibility: resolve_visibility(template.visibility)
    ]
    |> put_help_links(template.help_links)
    |> put_metadata(template.metadata)
  end

  defp put_help_links(opts, []), do: opts

  defp put_help_links(opts, links) do
    Keyword.put(opts, :help, %{links: Enum.map(links, &help_link_to_map/1)})
  end

  defp put_metadata(opts, []), do: opts

  defp put_metadata(opts, entries) do
    Keyword.put(opts, :metadata, Map.new(entries, &metadata_entry_to_pair/1))
  end

  defp metadata_entry_to_pair(%{key: key, value: value, visibility: :VISIBILITY_UNSPECIFIED}) do
    {key, value}
  end

  defp metadata_entry_to_pair(%{key: key, value: value, visibility: visibility}) do
    {key, {value, resolve_visibility(visibility)}}
  end

  defp resolve_visibility(:VISIBILITY_UNSPECIFIED), do: :INTERNAL
  defp resolve_visibility(v), do: Map.fetch!(@visibility_mapping, v)

  defp help_link_to_map(link) do
    %{url: link.url, description: link.description}
  end

  defp require_nonempty!(nil, field) do
    raise ArgumentError, "error extension template.#{field} is required"
  end

  defp require_nonempty!("", field) do
    raise ArgumentError, "error extension template.#{field} must not be empty"
  end

  defp require_nonempty!(value, _field) when is_binary(value), do: value

  defp require_code!(nil) do
    raise ArgumentError, "error extension template.code is required"
  end

  defp require_code!(:UNSPECIFIED) do
    raise ArgumentError, "error extension template.code must not be UNSPECIFIED"
  end

  defp require_code!(code) when code in @valid_codes, do: code

  defp require_code!(code) do
    raise ArgumentError,
          "error extension template.code is invalid: #{inspect(code)}, expected one of #{inspect(@valid_codes)}"
  end

  defp get_extension(nil, _tag), do: nil

  defp get_extension(%{__unknown_fields__: fields}, tag) do
    case Enum.find(fields, &(elem(&1, 0) == tag)) do
      {_, _, binary} -> binary
      nil -> nil
    end
  end
end
