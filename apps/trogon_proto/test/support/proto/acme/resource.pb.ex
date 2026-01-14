defmodule Acme.Resource.V1.ResourceId.IdentityVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "acme.resource.v1.ResourceId.IdentityVersion",
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
          options: %Google.Protobuf.EnumValueOptions{
            deprecated: false,
            features: nil,
            debug_redact: false,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [
              {870_002, 2,
               <<10, 24, 18, 22, 114, 101, 115, 111, 117, 114, 99, 101, 47, 123, 114, 101, 115, 111, 117, 114, 99, 101,
                 95, 105, 100, 125>>}
            ]
          },
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
           <<10, 36, 26, 34, 104, 116, 116, 112, 115, 58, 47, 47, 97, 99, 109, 101, 46, 101, 120, 97, 109, 112, 108,
             101, 46, 99, 111, 109, 47, 114, 101, 115, 111, 117, 114, 99, 101, 115>>}
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

defmodule Acme.Resource.V1.ResourceId do
  @moduledoc false

  use Protobuf,
    full_name: "acme.resource.v1.ResourceId",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "ResourceId",
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
              options: %Google.Protobuf.EnumValueOptions{
                deprecated: false,
                features: nil,
                debug_redact: false,
                feature_support: nil,
                uninterpreted_option: [],
                __pb_extensions__: %{},
                __unknown_fields__: [
                  {870_002, 2,
                   <<10, 24, 18, 22, 114, 101, 115, 111, 117, 114, 99, 101, 47, 123, 114, 101, 115, 111, 117, 114, 99,
                     101, 95, 105, 100, 125>>}
                ]
              },
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
               <<10, 36, 26, 34, 104, 116, 116, 112, 115, 58, 47, 47, 97, 99, 109, 101, 46, 101, 120, 97, 109, 112, 108,
                 101, 46, 99, 111, 109, 47, 114, 101, 115, 111, 117, 114, 99, 101, 115>>}
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
