if Code.ensure_loaded?(Protobuf) do
  defprotocol OnePiece.Commanded.ProtobufMapper do
    @moduledoc """
    Protocol for encoding and decoding `Protobuf` structs.

    The protocol is required when using the `OnePiece.Commanded.EventStore.ProtobufJsonbSerializer` serializer and
    working with Aggregate snapshotting. Since the Aggregates are not `Protobuf` structs, the serializer needs to
    encode and decode them to a `Protobuf` struct.

    ## Example

    ```elixir
    defmodule MyApp.MyAggregate do
      alias MyApp.Proto.MyAggregateProto

      use OnePiece.Commanded.Aggregate, identifier: :id

      embedded_schema do
        field(:initiated?, :boolean, default: false)
      end
    end


    defimpl OnePiece.Commanded.ProtobufMapper, for: MyApp.MyAggregate do
      alias MyApp.MyAggregate
      alias MyApp.Proto.MyAggregateProto

      def message_module(%MyAggregate{} = _aggregate), do: MyAggregateProto

      def to_proto_message(%MyAggregate{} = aggregate) do
        %MyAggregateProto{
          id: aggregate.id,
          initiated: aggregate.initiated?
        }
      end

      def from_proto_message(%MyAggregate{} = aggregate, %MyAggregateProto{} = proto_message) do
        aggregate
        |> Map.put(:id, proto_message.id)
        |> Map.put(:initiated?, proto_message.initiated)
      end
    end
    ```
    """

    @fallback_to_any true

    @doc """
    Given a struct, returns a `Protobuf` struct.

    The default implementation returns the message itself because implicitly expects the struct to be a
    `Protobuf` struct. No need to map the struct to the message.
    """
    def to_proto_message(message)

    @doc """
    Given the initial message, and the decoded `Protobuf` struct, returns the decoded term.

    The default implementation returns the decoded term itself because implicitly expects the initial message to be a
    `Protobuf` struct. No need to map the decoded term to the initial message.
    """
    def from_proto_message(message, term)

    @doc """
    Returns the module name of the `Protobuf` struct.

    The default implementation returns the struct name of the message because implicitly expects the struct to be a
    `Protobuf` struct. No need to map the struct to the message.
    """
    def proto_module(message)
  end

  defimpl OnePiece.Commanded.ProtobufMapper, for: Any do
    def to_proto_message(message) do
      message
    end

    def from_proto_message(_message, term) do
      term
    end

    def proto_module(%module_name{} = _message) do
      module_name
    end
  end
end
