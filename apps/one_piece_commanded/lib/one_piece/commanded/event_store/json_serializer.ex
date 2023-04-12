defmodule OnePiece.Commanded.EventStore.JsonbSerializer do
  @moduledoc """
  A JSONB serializer based on events defined by `OnePiece.Commanded.Event`.

  It uses `OnePiece.Commanded.Event` to cast the event to the correct type, by proxying, using `Ecto.Schema`s and
  `Ecto.Changeset`s.

  ## Configuring

  To use this serializer, add it to your `config.exs`:

      config :my_app, MyApp.EventStore,
        serializer: OnePiece.Commanded.EventStore.JsonbSerializer,
        types: EventStore.PostgresTypes
  """

  alias Commanded.EventStore.TypeProvider

  @doc """
  Serialize given term to JSON binary data.

  It is just a passthrough, since `EventStore.PostgresTypes` will take care of the serialization.
  """
  def serialize(term), do: term

  @doc """
  Deserialize given JSON binary data to the expected type.

  It is already a map since `EventStore.PostgresTypes` will take care of the deserialization. Then, it will use
  `OnePiece.Commanded.Event` to cast the event to the correct type.
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

  defp run_casting(%module_name{} = _event, term) do
    module_name.new!(term)
  end
end
