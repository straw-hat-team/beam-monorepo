if Code.ensure_loaded?(Protobuf) do
  defmodule OnePiece.Commanded.EventStore.ProtobufJsonbSerializer do
    @moduledoc """
    A JSONB serializer using `Protobuf.JSON`.

    ## Configuring

    To use this serializer, add it to your `config.exs`:

        config :my_app, MyApp.EventStore,
            serializer: OnePiece.Commanded.EventStore.ProtobufJsonbSerializer,
            types: EventStore.PostgresTypes


    ## Aggregate Snapshots

    To serialize aggregate snapshots, you need to implement the `OnePiece.Commanded.ProtobufMapper` protocol.
    """

    alias Commanded.EventStore.TypeProvider
    alias OnePiece.Commanded.ProtobufMapper

    @encode_opts [use_proto_names: false, use_enum_numbers: false, emit_unpopulated: true]

    @doc """
    Convert given `Protobuf` struct to a map.
    """
    def serialize(term) when is_struct(term) do
      term = ProtobufMapper.to_proto_message(term)

      case Protobuf.JSON.to_encodable(term, @encode_opts) do
        {:ok, encodable} -> encodable
        {:error, error} -> raise error
      end
    end

    def serialize(term) do
      term
    end

    @doc """
    Convert given map to a `Protobuf` struct.
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

    defp run_casting(message, term) do
      message_module = ProtobufMapper.proto_module(message)

      case Protobuf.JSON.from_decoded(term, message_module) do
        {:ok, decoded} -> ProtobufMapper.from_proto_message(message, decoded)
        {:error, error} -> raise error
      end
    end
  end
end
