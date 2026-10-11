defmodule Invalid.NoFormat.V1.NoFormatId.IdentityVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "invalid.no_format.v1.NoFormatId.IdentityVersion",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "IdentityVersion",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "IDENTITY_VERSION_UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "IDENTITY_VERSION_V1",
          number: 1,
          options: nil,
          __unknown_fields__: []
        }
      ],
      options: %Google.Protobuf.EnumOptions{
        allow_alias: nil,
        deprecated: false,
        deprecated_legacy_json_field_conflicts: nil,
        features: nil,
        uninterpreted_option: [],
        __pb_extensions__: %{},
        __unknown_fields__: [
          {870_001, 2,
           <<10, 21, 18, 19, 105, 110, 118, 97, 108, 105, 100, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109>>}
        ]
      },
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:IDENTITY_VERSION_UNSPECIFIED, 0)
  field(:IDENTITY_VERSION_V1, 1)
end

defmodule Invalid.NoFormat.V1.NoFormatId do
  @moduledoc false

  use Protobuf,
    full_name: "invalid.no_format.v1.NoFormatId",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "NoFormatId",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "value",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "value",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [
        %Google.Protobuf.EnumDescriptorProto{
          name: "IdentityVersion",
          value: [
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "IDENTITY_VERSION_UNSPECIFIED",
              number: 0,
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "IDENTITY_VERSION_V1",
              number: 1,
              options: nil,
              __unknown_fields__: []
            }
          ],
          options: %Google.Protobuf.EnumOptions{
            allow_alias: nil,
            deprecated: false,
            deprecated_legacy_json_field_conflicts: nil,
            features: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [
              {870_001, 2,
               <<10, 21, 18, 19, 105, 110, 118, 97, 108, 105, 100, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111,
                 109>>}
            ]
          },
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        }
      ],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:value, 1, type: :string)
end
