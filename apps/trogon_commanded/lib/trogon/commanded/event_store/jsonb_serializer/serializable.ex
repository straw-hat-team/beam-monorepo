defprotocol Trogon.Commanded.EventStore.JsonbSerializer.Serializable do
  @moduledoc """
  Converts a struct to and from the JSON-compatible term stored by
  `Trogon.Commanded.EventStore.JsonbSerializer`.

  Aggregates using the `v2` feature of `Trogon.Commanded.Aggregate` implement it
  with `Ecto.embedded_dump/2` and `Ecto.embedded_load/3`:

      alias Trogon.Commanded.EventStore.JsonbSerializer.Serializable

      json =
        account
        |> Serializable.serialize()
        |> Jason.encode!()

      account = Serializable.deserialize(%MyApp.BankAccount{}, Jason.decode!(json))

  Any other struct falls back to returning the struct as is on `serialize/1`,
  and to `new!/1` on `deserialize/2`.

  Implement it for your own structs to control how they are stored.
  """

  @fallback_to_any true

  @doc """
  Converts the struct to a JSON-compatible term.
  """
  @spec serialize(struct()) :: term()
  def serialize(struct)

  @doc """
  Builds the struct back from the decoded JSON term, dispatching on an empty
  struct of the expected module.
  """
  @spec deserialize(struct(), map()) :: struct()
  def deserialize(empty_struct, term)
end

defimpl Trogon.Commanded.EventStore.JsonbSerializer.Serializable, for: Any do
  def serialize(struct), do: struct

  def deserialize(%module{}, term), do: module.new!(term)
end
