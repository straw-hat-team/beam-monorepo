defmodule Trogon.Ecto.ErrorMessage do
  @moduledoc false

  @spec interpolate({String.t(), keyword()}) :: String.t()
  def interpolate({message, opts}) do
    Enum.reduce(opts, message, &replace_binding/2)
  end

  @spec interpolates?(String.t(), atom()) :: boolean()
  def interpolates?(message, key) do
    String.contains?(message, placeholder(key))
  end

  defp replace_binding({key, value}, message) do
    placeholder = placeholder(key)

    if String.contains?(message, placeholder) do
      String.replace(message, placeholder, stringify(value))
    else
      message
    end
  end

  defp placeholder(key), do: "%{#{key}}"

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_number(value), do: to_string(value)
  defp stringify(value) when is_atom(value) and not is_nil(value), do: to_string(value)
  defp stringify(value), do: inspect(value)
end
