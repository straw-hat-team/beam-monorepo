defmodule Trogon.Commanded.EventStore.JsonbSerializer do
  @moduledoc """
  A JSONB serializer based on events defined by `Trogon.Commanded.Event`.

  It uses `Trogon.Commanded.Event` to cast the event to the correct type, by proxying, using `Ecto.Schema`s and
  `Ecto.Changeset`s.

  ## Configuring

  To use this serializer, add it to your `config.exs`:

      config :my_app, MyApp.EventStore,
        serializer: Trogon.Commanded.EventStore.JsonbSerializer,
        types: EventStore.PostgresTypes
  """

  alias Commanded.EventStore.TypeProvider
  alias Trogon.Commanded.EventStore.JsonbSerializer.Serializable

  @doc """
  Serialize given term to JSON binary data.

  It is just a passthrough, since `EventStore.PostgresTypes` will take care of the serialization. Aggregates using
  the `v2` feature of `Trogon.Commanded.Aggregate` are serialized through `Trogon.Commanded.EventStore.JsonbSerializer.Serializable` first.
  """
  def serialize(%_{} = term), do: Serializable.serialize(term)

  def serialize(term), do: term

  @doc """
  Deserialize given JSON binary data to the expected type.

  It is already a map since `EventStore.PostgresTypes` will take care of the deserialization. Then, it will use
  `Trogon.Commanded.Event` to cast the event to the correct type. Aggregates using the `v2` feature of
  `Trogon.Commanded.Aggregate` are deserialized through `Trogon.Commanded.EventStore.JsonbSerializer.Serializable` instead.
  """
  def deserialize(term, config \\ [])

  def deserialize(term, config) do
    case Keyword.get(config, :type) do
      nil ->
        term

      type ->
        type
        |> TypeProvider.to_struct()
        |> run_casting(term)
    end
  end

  defp run_casting(%_{} = empty_struct, term) do
    Serializable.deserialize(empty_struct, term)
  end
end
