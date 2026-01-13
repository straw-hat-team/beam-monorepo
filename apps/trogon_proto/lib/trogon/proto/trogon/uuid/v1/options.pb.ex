defmodule TrogonProto.Uuid.V1.FileOptions do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.uuid.v1.FileOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "FileOptions",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "namespace",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.uuid.v1.Namespace",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "namespace",
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
          name: "_namespace",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:namespace, 1, proto3_optional: true, type: TrogonProto.Uuid.V1.Namespace)
end

defmodule TrogonProto.Uuid.V1.EnumOptions do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.uuid.v1.EnumOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "EnumOptions",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "namespace",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.uuid.v1.Namespace",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "namespace",
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
          name: "_namespace",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:namespace, 1, proto3_optional: true, type: TrogonProto.Uuid.V1.Namespace)
end

defmodule TrogonProto.Uuid.V1.EnumValueOptions.Format do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.uuid.v1.EnumValueOptions.Format",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Format",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "namespace",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.uuid.v1.Namespace",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "namespace",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "template",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "template",
          proto3_optional: nil,
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
          name: "_namespace",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:namespace, 1, proto3_optional: true, type: TrogonProto.Uuid.V1.Namespace)
  field(:template, 2, type: :string)
end

defmodule TrogonProto.Uuid.V1.EnumValueOptions do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.uuid.v1.EnumValueOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "EnumValueOptions",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "format",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.uuid.v1.EnumValueOptions.Format",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "format",
          proto3_optional: true,
          __unknown_fields__: []
        }
      ],
      nested_type: [
        %Google.Protobuf.DescriptorProto{
          name: "Format",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "namespace",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_MESSAGE,
              type_name: ".trogon.uuid.v1.Namespace",
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "namespace",
              proto3_optional: true,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "template",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "template",
              proto3_optional: nil,
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
              name: "_namespace",
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
          name: "_format",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:format, 1, proto3_optional: true, type: TrogonProto.Uuid.V1.EnumValueOptions.Format)
end
