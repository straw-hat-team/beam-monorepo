defmodule OnePiece.Commanded.Helpers do
  @moduledoc """
  A Swiss Army Knife Helper Module.
  """

  @doc """
  Deprecated, it has the same behavior as `OnePiece.Commanded.Id.new/0`.
  """
  @spec generate_uuid :: String.t()
  @deprecated "Use `OnePiece.Commanded.Id.new/0` instead."
  defdelegate generate_uuid, to: OnePiece.Commanded.Id, as: :new

  @doc """
  Transforms the given `source` map or struct into the `target` struct.
  """
  @spec struct_from(source :: struct(), target :: struct()) :: struct()
  def struct_from(%_{} = source, target) do
    struct(target, Map.from_struct(source))
  end

  @spec struct_from(attrs :: map(), target :: module()) :: struct()
  def struct_from(attrs, target) do
    struct(target, attrs)
  end

  @doc false
  @spec defines_struct?(mod :: module()) :: boolean()
  def defines_struct?(mod) do
    :functions
    |> mod.__info__()
    |> Keyword.get(:__struct__)
    |> Kernel.!=(nil)
  end

  @doc """
  Copy the information from the `params` map into the given `target` map.

      iex> OnePiece.Commanded.Helpers.cast_to(%{}, %{name: "ubi-wan", last_name: "kenobi"}, [:last_name])
      %{last_name: "kenobi"}
  """
  @spec cast_to(target :: map, params :: map, keys :: [Map.key]) :: map
  def cast_to(target, params, keys) do
    Enum.reduce(keys, target, &Map.put(&2, &1, Map.get(params, &1)))
  end
end
