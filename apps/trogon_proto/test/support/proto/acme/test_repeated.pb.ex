defmodule Acme.Test.V1.TestRepeated do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.TestRepeated",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "TestRepeated",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "database_url",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: %Google.Protobuf.FieldOptions{
            ctype: :STRING,
            packed: nil,
            deprecated: false,
            lazy: false,
            jstype: :JS_NORMAL,
            weak: false,
            unverified_lazy: false,
            debug_redact: false,
            retention: nil,
            targets: [],
            edition_defaults: [],
            features: nil,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [{870_003, 2, <<10, 2, 8, 2>>}]
          },
          oneof_index: nil,
          json_name: "databaseUrl",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "tags",
          extendee: nil,
          number: 2,
          label: :LABEL_REPEATED,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: %Google.Protobuf.FieldOptions{
            ctype: :STRING,
            packed: nil,
            deprecated: false,
            lazy: false,
            jstype: :JS_NORMAL,
            weak: false,
            unverified_lazy: false,
            debug_redact: false,
            retention: nil,
            targets: [],
            edition_defaults: [],
            features: nil,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [{870_003, 2, <<10, 6, 8, 1, 34, 2, 44, 32>>}]
          },
          oneof_index: nil,
          json_name: "tags",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "port_list",
          extendee: nil,
          number: 3,
          label: :LABEL_REPEATED,
          type: :TYPE_INT32,
          type_name: nil,
          default_value: nil,
          options: %Google.Protobuf.FieldOptions{
            ctype: :STRING,
            packed: nil,
            deprecated: false,
            lazy: false,
            jstype: :JS_NORMAL,
            weak: false,
            unverified_lazy: false,
            debug_redact: false,
            retention: nil,
            targets: [],
            edition_defaults: [],
            features: nil,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [{870_003, 2, <<10, 6, 8, 1, 34, 2, 44, 32>>}]
          },
          oneof_index: nil,
          json_name: "portList",
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

  field(:database_url, 1, type: :string, json_name: "databaseUrl", deprecated: false)
  field(:tags, 2, repeated: true, type: :string, deprecated: false)
  field(:port_list, 3, repeated: true, type: :int32, json_name: "portList", deprecated: false)
end
