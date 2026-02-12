defmodule Trogon.Commanded.ObjectId.ValidationError do
  @moduledoc """
  Raised when an ObjectId value is invalid.
  """
  defexception [:module, :value, :reason]

  @impl true
  def message(%{module: module, value: value, reason: reason}) do
    "invalid #{inspect(module)} value: #{inspect(value)} (#{reason})"
  end
end
