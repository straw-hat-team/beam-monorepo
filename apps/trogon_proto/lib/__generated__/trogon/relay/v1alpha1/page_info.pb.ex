defmodule TrogonProto.Relay.V1Alpha1.PageInfo do
  @moduledoc """
  PageInfo provides cursor-based pagination information for Relay connections.

  This message follows the Relay GraphQL Connection specification and contains
  metadata about the current page in a cursor-paginated result set.

  Example usage:

    import "trogon/relay/v1alpha1/page_info.proto";

    message UserConnection {
      repeated UserEdge edges = 1;
      trogon.relay.v1alpha1.PageInfo page_info = 2;
    }
  """

  use Protobuf,
    full_name: "trogon.relay.v1alpha1.PageInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "PageInfo",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "has_next_page",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_BOOL,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "hasNextPage",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "has_previous_page",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_BOOL,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "hasPreviousPage",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "start_cursor",
          extendee: nil,
          number: 3,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "startCursor",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "end_cursor",
          extendee: nil,
          number: 4,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 1,
          json_name: "endCursor",
          proto3_optional: true,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{
          name: "_start_cursor",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{
          name: "_end_cursor",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:has_next_page, 1, type: :bool, json_name: "hasNextPage")
  field(:has_previous_page, 2, type: :bool, json_name: "hasPreviousPage")
  field(:start_cursor, 3, proto3_optional: true, type: :string, json_name: "startCursor")
  field(:end_cursor, 4, proto3_optional: true, type: :string, json_name: "endCursor")
end
