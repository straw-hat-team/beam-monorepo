defmodule TrogonProto.Error.V1Alpha1.MessageOptions.Template do
  @moduledoc """
  Template defines the static error template for a message that can be
  adapted into a runtime error representation.

  These fields are intentionally language-neutral so both Elixir and Go
  runtimes can derive their native error template APIs from the same proto
  annotation.
  """

  use Protobuf,
    full_name: "trogon.error.v1alpha1.MessageOptions.Template",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Template",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "domain",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "domain",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "reason",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 1,
          json_name: "reason",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "message",
          extendee: nil,
          number: 3,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 2,
          json_name: "message",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "code",
          extendee: nil,
          number: 4,
          label: :LABEL_OPTIONAL,
          type: :TYPE_ENUM,
          type_name: ".trogon.error.v1alpha1.Code",
          default_value: nil,
          options: nil,
          oneof_index: 3,
          json_name: "code",
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
          name: "_domain",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{
          name: "_reason",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{
          name: "_message",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{name: "_code", options: nil, __unknown_fields__: []}
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:domain, 1, proto3_optional: true, type: :string)
  field(:reason, 2, proto3_optional: true, type: :string)
  field(:message, 3, proto3_optional: true, type: :string)
  field(:code, 4, proto3_optional: true, type: TrogonProto.Error.V1Alpha1.Code, enum: true)
end

defmodule TrogonProto.Error.V1Alpha1.MessageOptions do
  @moduledoc """
  MessageOptions defines message-level options for error payload messages.
  """

  use Protobuf,
    full_name: "trogon.error.v1alpha1.MessageOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "MessageOptions",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "template",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.error.v1alpha1.MessageOptions.Template",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "template",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [
        %Google.Protobuf.DescriptorProto{
          name: "Template",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "domain",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 0,
              json_name: "domain",
              proto3_optional: true,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "reason",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 1,
              json_name: "reason",
              proto3_optional: true,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "message",
              extendee: nil,
              number: 3,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: 2,
              json_name: "message",
              proto3_optional: true,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "code",
              extendee: nil,
              number: 4,
              label: :LABEL_OPTIONAL,
              type: :TYPE_ENUM,
              type_name: ".trogon.error.v1alpha1.Code",
              default_value: nil,
              options: nil,
              oneof_index: 3,
              json_name: "code",
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
              name: "_domain",
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.OneofDescriptorProto{
              name: "_reason",
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.OneofDescriptorProto{
              name: "_message",
              options: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.OneofDescriptorProto{
              name: "_code",
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
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:template, 1, type: TrogonProto.Error.V1Alpha1.MessageOptions.Template)
end
