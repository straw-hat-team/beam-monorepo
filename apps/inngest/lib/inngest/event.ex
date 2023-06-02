defmodule Inngest.Event do
  @enforce_keys [:name]
  defstruct [:name, :data, :user, :ts, :v]

  defimpl Jason.Encoder do
    def encode(value, opts) do
      value
      |> Map.from_struct()
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Jason.Encode.map(opts)
    end
  end
end
