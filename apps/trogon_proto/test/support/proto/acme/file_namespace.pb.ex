defmodule Acme.FileNamespace.V1.FileNamespaceId.IdentityVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "acme.file_namespace.v1.FileNamespaceId.IdentityVersion",
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
              {870_002, 2, <<10, 16, 18, 14, 102, 105, 108, 101, 47, 123, 102, 105, 108, 101, 95, 105, 100, 125>>}
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

  field(:IDENTITY_VERSION_UNSPECIFIED, 0)
  field(:IDENTITY_VERSION_V1, 1)
end

defmodule Acme.FileNamespace.V1.FileNamespaceId do
  @moduledoc false

  use Protobuf,
    full_name: "acme.file_namespace.v1.FileNamespaceId",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "FileNamespaceId",
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
                  {870_002, 2, <<10, 16, 18, 14, 102, 105, 108, 101, 47, 123, 102, 105, 108, 101, 95, 105, 100, 125>>}
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
