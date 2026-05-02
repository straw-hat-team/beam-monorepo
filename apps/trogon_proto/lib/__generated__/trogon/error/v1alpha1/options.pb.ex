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
          oneof_index: nil,
          json_name: "domain",
          proto3_optional: nil,
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
          oneof_index: nil,
          json_name: "reason",
          proto3_optional: nil,
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
          oneof_index: nil,
          json_name: "message",
          proto3_optional: nil,
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
          oneof_index: nil,
          json_name: "code",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "visibility",
          extendee: nil,
          number: 5,
          label: :LABEL_OPTIONAL,
          type: :TYPE_ENUM,
          type_name: ".trogon.error.v1alpha1.Visibility",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "visibility",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "help_links",
          extendee: nil,
          number: 6,
          label: :LABEL_REPEATED,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.error.v1alpha1.MessageOptions.HelpLink",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "helpLinks",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
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

  field(:domain, 1, type: :string)
  field(:reason, 2, type: :string)
  field(:message, 3, type: :string)
  field(:code, 4, type: TrogonProto.Error.V1Alpha1.Code, enum: true)
  field(:visibility, 5, type: TrogonProto.Error.V1Alpha1.Visibility, enum: true)

  field(:help_links, 6,
    repeated: true,
    type: TrogonProto.Error.V1Alpha1.MessageOptions.HelpLink,
    json_name: "helpLinks"
  )
end

defmodule TrogonProto.Error.V1Alpha1.MessageOptions.HelpLink do
  @moduledoc """
  HelpLink is a single documentation or support link.
  """

  use Protobuf,
    full_name: "trogon.error.v1alpha1.MessageOptions.HelpLink",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "HelpLink",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "url",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "url",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "description",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "description",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
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

  field(:url, 1, type: :string)
  field(:description, 2, type: :string)
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
              oneof_index: nil,
              json_name: "domain",
              proto3_optional: nil,
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
              oneof_index: nil,
              json_name: "reason",
              proto3_optional: nil,
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
              oneof_index: nil,
              json_name: "message",
              proto3_optional: nil,
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
              oneof_index: nil,
              json_name: "code",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "visibility",
              extendee: nil,
              number: 5,
              label: :LABEL_OPTIONAL,
              type: :TYPE_ENUM,
              type_name: ".trogon.error.v1alpha1.Visibility",
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "visibility",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "help_links",
              extendee: nil,
              number: 6,
              label: :LABEL_REPEATED,
              type: :TYPE_MESSAGE,
              type_name: ".trogon.error.v1alpha1.MessageOptions.HelpLink",
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "helpLinks",
              proto3_optional: nil,
              __unknown_fields__: []
            }
          ],
          nested_type: [],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [],
          reserved_range: [],
          reserved_name: [],
          __unknown_fields__: []
        },
        %Google.Protobuf.DescriptorProto{
          name: "HelpLink",
          field: [
            %Google.Protobuf.FieldDescriptorProto{
              name: "url",
              extendee: nil,
              number: 1,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "url",
              proto3_optional: nil,
              __unknown_fields__: []
            },
            %Google.Protobuf.FieldDescriptorProto{
              name: "description",
              extendee: nil,
              number: 2,
              label: :LABEL_OPTIONAL,
              type: :TYPE_STRING,
              type_name: nil,
              default_value: nil,
              options: nil,
              oneof_index: nil,
              json_name: "description",
              proto3_optional: nil,
              __unknown_fields__: []
            }
          ],
          nested_type: [],
          enum_type: [],
          extension_range: [],
          extension: [],
          options: nil,
          oneof_decl: [],
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

defmodule TrogonProto.Error.V1Alpha1.FieldOptions do
  @moduledoc """
  FieldOptions defines field-level options for error payload message fields.
  """

  use Protobuf,
    full_name: "trogon.error.v1alpha1.FieldOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "FieldOptions",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "visibility",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_ENUM,
          type_name: ".trogon.error.v1alpha1.Visibility",
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "visibility",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "default_value",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "defaultValue",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "value",
          extendee: nil,
          number: 3,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "value",
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
          name: "value_policy",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  oneof(:value_policy, 0)

  field(:visibility, 1, type: TrogonProto.Error.V1Alpha1.Visibility, enum: true)
  field(:default_value, 2, type: :string, json_name: "defaultValue", oneof: 0)
  field(:value, 3, type: :string, oneof: 0)
end
