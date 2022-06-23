defmodule OnePiece.Commanded do
  @moduledoc """
  Extend `Commanded` package. A swiss army knife for applications following Domain-Driven Design (DDD), Event Sourcing
  (ES), and Command and Query Responsibility Segregation (CQRS).
  """

  @doc """
  Copy the information from the `params` map into the given `target` map.

      iex> OnePiece.Commanded.cast_to(%{}, %{name: "ubi-wan", last_name: "kenobi"}, [:last_name])
      %{last_name: "kenobi"}
  """
  @spec cast_to(target :: map, params :: map, keys :: [Map.key]) :: map
  def cast_to(target, params, keys) do
    Enum.reduce(keys, target, &Map.put(&2, &1, Map.get(params, &1)))
  end
end
