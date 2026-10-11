defmodule Acme.Singleton.V1.SingletonId.IdentityVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "acme.singleton.v1.SingletonId.IdentityVersion",
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
               <<10, 18, 18, 16, 115, 116, 97, 116, 105, 99, 95, 115, 105, 110, 103, 108, 101, 116, 111, 110>>}
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
          {870_001, 2, <<10, 18, 18, 16, 97, 99, 109, 101, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109>>}
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

defmodule Acme.Singleton.V1.SingletonId do
  @moduledoc false

  use Protobuf,
    full_name: "acme.singleton.v1.SingletonId",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "SingletonId",
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
                   <<10, 18, 18, 16, 115, 116, 97, 116, 105, 99, 95, 115, 105, 110, 103, 108, 101, 116, 111, 110>>}
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
              {870_001, 2, <<10, 18, 18, 16, 97, 99, 109, 101, 46, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109>>}
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
