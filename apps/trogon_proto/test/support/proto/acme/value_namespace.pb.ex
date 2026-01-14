defmodule Acme.ValueNamespace.V1.ValueNamespaceId.IdentityVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "acme.value_namespace.v1.ValueNamespaceId.IdentityVersion",
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
               <<10, 18, 18, 16, 118, 97, 108, 117, 101, 47, 123, 118, 97, 108, 117, 101, 95, 105, 100, 125>>}
            ]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "IDENTITY_VERSION_V2",
          number: 2,
          options: %Google.Protobuf.EnumValueOptions{
            deprecated: false,
            features: nil,
            debug_redact: false,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [
              {870_002, 2,
               <<10, 42, 10, 22, 18, 20, 118, 97, 108, 117, 101, 45, 108, 101, 118, 101, 108, 46, 97, 99, 109, 101, 46,
                 99, 111, 109, 18, 16, 118, 97, 108, 117, 101, 47, 123, 118, 97, 108, 117, 101, 95, 105, 100, 125>>}
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
           <<10, 21, 18, 19, 101, 110, 117, 109, 45, 108, 101, 118, 101, 108, 46, 97, 99, 109, 101, 46, 99, 111, 109>>}
        ]
      },
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:IDENTITY_VERSION_UNSPECIFIED, 0)
  field(:IDENTITY_VERSION_V1, 1)
  field(:IDENTITY_VERSION_V2, 2)
end

defmodule Acme.ValueNamespace.V1.ValueNamespaceId do
  @moduledoc false

  use Protobuf,
    full_name: "acme.value_namespace.v1.ValueNamespaceId",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "ValueNamespaceId",
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
                   <<10, 18, 18, 16, 118, 97, 108, 117, 101, 47, 123, 118, 97, 108, 117, 101, 95, 105, 100, 125>>}
                ]
              },
              __unknown_fields__: []
            },
            %Google.Protobuf.EnumValueDescriptorProto{
              name: "IDENTITY_VERSION_V2",
              number: 2,
              options: %Google.Protobuf.EnumValueOptions{
                deprecated: false,
                features: nil,
                debug_redact: false,
                feature_support: nil,
                uninterpreted_option: [],
                __pb_extensions__: %{},
                __unknown_fields__: [
                  {870_002, 2,
                   <<10, 42, 10, 22, 18, 20, 118, 97, 108, 117, 101, 45, 108, 101, 118, 101, 108, 46, 97, 99, 109, 101,
                     46, 99, 111, 109, 18, 16, 118, 97, 108, 117, 101, 47, 123, 118, 97, 108, 117, 101, 95, 105, 100,
                     125>>}
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
               <<10, 21, 18, 19, 101, 110, 117, 109, 45, 108, 101, 118, 101, 108, 46, 97, 99, 109, 101, 46, 99, 111,
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
