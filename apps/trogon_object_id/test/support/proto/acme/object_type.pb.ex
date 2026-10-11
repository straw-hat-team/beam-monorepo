defmodule Acme.Type.V1.ObjectType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "acme.type.v1.ObjectType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "ObjectType",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "OBJECT_TYPE_UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "OBJECT_TYPE_TICKET",
          number: 1,
          options: %Google.Protobuf.EnumValueOptions{
            deprecated: false,
            features: nil,
            debug_redact: false,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [{870_010, 2, <<10, 6, 116, 105, 99, 107, 101, 116>>}]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "OBJECT_TYPE_WORKSPACE",
          number: 2,
          options: %Google.Protobuf.EnumValueOptions{
            deprecated: false,
            features: nil,
            debug_redact: false,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [
              {870_010, 2, <<10, 9, 119, 111, 114, 107, 115, 112, 97, 99, 101, 18, 1, 35>>}
            ]
          },
          __unknown_fields__: []
        }
      ],
      options: nil,
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field :OBJECT_TYPE_UNSPECIFIED, 0
  field :OBJECT_TYPE_TICKET, 1
  field :OBJECT_TYPE_WORKSPACE, 2
end
