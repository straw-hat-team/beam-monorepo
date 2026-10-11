defmodule Trogon.ObjectId.ProtoExtension do
  @moduledoc false

  @spec find_enum_value_extension!(module(), atom(), non_neg_integer(), String.t()) :: binary()
  def find_enum_value_extension!(enum_module, value, tag, extension_name) do
    desc = enum_module.descriptor()
    value_name = Atom.to_string(value)
    value_desc = Enum.find(desc.value, &(&1.name == value_name))

    case value_desc do
      nil ->
        available = Enum.map(desc.value, &String.to_atom(&1.name))

        raise ArgumentError,
              "Enum value #{inspect(value)} not found. Available values: #{inspect(available)}"

      %{options: nil} ->
        raise ArgumentError,
              "No options found for #{inspect(value)}. " <>
                "Add (#{extension_name}) to the proto enum value."

      %{options: %{__unknown_fields__: fields}} ->
        case find_field(fields, tag) do
          nil ->
            raise ArgumentError,
                  "No #{extension_name} extension found for #{inspect(value)}. " <>
                    "Add (#{extension_name}) to the proto enum value."

          binary ->
            binary
        end
    end
  end

  defp find_field(fields, tag) do
    case Enum.find(fields, &(elem(&1, 0) == tag)) do
      {_, _, binary} -> binary
      nil -> nil
    end
  end
end
