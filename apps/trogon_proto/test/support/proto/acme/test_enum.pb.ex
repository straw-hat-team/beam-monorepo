defmodule Acme.Test.V1.LogLevel do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "acme.test.v1.LogLevel",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "LogLevel",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "LOG_LEVEL_UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "LOG_LEVEL_DEBUG",
          number: 1,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "LOG_LEVEL_INFO",
          number: 2,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "LOG_LEVEL_WARN",
          number: 3,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "LOG_LEVEL_ERROR",
          number: 4,
          options: nil,
          __unknown_fields__: []
        }
      ],
      options: nil,
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field :LOG_LEVEL_UNSPECIFIED, 0
  field :LOG_LEVEL_DEBUG, 1
  field :LOG_LEVEL_INFO, 2
  field :LOG_LEVEL_WARN, 3
  field :LOG_LEVEL_ERROR, 4
end

defmodule Acme.Test.V1.TestEnumConfig do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.TestEnumConfig",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "TestEnumConfig",
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
          name: "log_level",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_ENUM,
          type_name: ".acme.test.v1.LogLevel",
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
            __unknown_fields__: [
              {870_003, 2,
               <<10, 18, 8, 1, 18, 14, 76, 79, 71, 95, 76, 69, 86, 69, 76, 95, 73, 78, 70, 79>>}
            ]
          },
          oneof_index: nil,
          json_name: "logLevel",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "log_levels",
          extendee: nil,
          number: 3,
          label: :LABEL_REPEATED,
          type: :TYPE_ENUM,
          type_name: ".acme.test.v1.LogLevel",
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
            __unknown_fields__: [{870_003, 2, <<10, 9, 8, 1, 34, 1, 44, 42, 2, 10, 0>>}]
          },
          oneof_index: nil,
          json_name: "logLevels",
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

  field :database_url, 1, type: :string, json_name: "databaseUrl", deprecated: false

  field :log_level, 2,
    type: Acme.Test.V1.LogLevel,
    json_name: "logLevel",
    enum: true,
    deprecated: false

  field :log_levels, 3,
    repeated: true,
    type: Acme.Test.V1.LogLevel,
    json_name: "logLevels",
    enum: true,
    deprecated: false
end
