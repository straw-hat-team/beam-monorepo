defmodule TrogonProto.Relay.V1Alpha1.CursorPagination.Forward do
  @moduledoc """
  Forward specifies parameters for forward pagination direction.
  """

  use Protobuf,
    full_name: "trogon.relay.v1alpha1.CursorPagination.Forward",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Forward",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "first",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_UINT32,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "first",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "after",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "after",
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
          name: "_after",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field :first, 1, type: :uint32
  field :after, 2, proto3_optional: true, type: :string
end

defmodule TrogonProto.Relay.V1Alpha1.CursorPagination.Backward do
  @moduledoc """
  Backward specifies parameters for backward pagination direction.
  """

  use Protobuf,
    full_name: "trogon.relay.v1alpha1.CursorPagination.Backward",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Backward",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "last",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_UINT32,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "last",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "before",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "before",
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
          name: "_before",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field :last, 1, type: :uint32
  field :before, 2, proto3_optional: true, type: :string
end

defmodule TrogonProto.Relay.V1Alpha1.CursorPagination do
  @moduledoc """
  CursorPagination represents cursor-based pagination parameters.

  Use this message to specify pagination parameters in list query requests
  following the Relay specification.

  Enforces Relay constraints:
  - Exactly one of Forward or Backward must be specified
  - Parameters for each direction are logically grouped

  Example usage:

    import "trogon/relay/v1alpha1/cursor_pagination.proto";

    message ListUsersRequest {
      trogon.relay.v1alpha1.CursorPagination pagination = 1;
    }
  """

  use Protobuf,
    full_name: "trogon.relay.v1alpha1.CursorPagination",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "CursorPagination",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "forward",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.relay.v1alpha1.CursorPagination.Forward",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "forward",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "backward",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.relay.v1alpha1.CursorPagination.Backward",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "backward",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [
        %Google.Protobuf.DescriptorProto{
          name: "Forward",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "first",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_UINT32,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "first",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "after",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "after",
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
              name: "_after",
              options: nil,
              __unknown_fields__: []
            }
          ],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        },
        %Google.Protobuf.DescriptorProto{
          name: "Backward",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "last",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_UINT32,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "last",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "before",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "before",
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
              name: "_before",
              options: nil,
              __unknown_fields__: []
            }
          ],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        }
      ],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{
          name: "direction",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  oneof :direction, 0

  field :forward, 1, type: TrogonProto.Relay.V1Alpha1.CursorPagination.Forward, oneof: 0
  field :backward, 2, type: TrogonProto.Relay.V1Alpha1.CursorPagination.Backward, oneof: 0
end
