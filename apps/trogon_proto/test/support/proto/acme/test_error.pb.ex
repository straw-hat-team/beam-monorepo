defmodule Acme.Test.V1.UserNotFoundError do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.UserNotFoundError",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "UserNotFoundError",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "user_id",
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
            __unknown_fields__: [{870_013, 2, <<8, 2>>}]
          },
          oneof_index: nil,
          json_name: "userId",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "internal_trace",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "internalTrace",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "service",
          extendee: nil,
          number: 3,
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
            __unknown_fields__: [
              {870_013, 2, <<8, 2, 18, 8, 117, 115, 101, 114, 45, 97, 112, 105>>}
            ]
          },
          oneof_index: nil,
          json_name: "service",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "region",
          extendee: nil,
          number: 4,
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
            __unknown_fields__: [
              {870_013, 2, <<8, 2, 26, 9, 117, 115, 45, 101, 97, 115, 116, 45, 49>>}
            ]
          },
          oneof_index: nil,
          json_name: "region",
          proto3_optional: nil,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: %Google.Protobuf.MessageOptions{
        message_set_wire_format: false,
        no_standard_descriptor_accessor: false,
        deprecated: false,
        map_entry: nil,
        deprecated_legacy_json_field_conflicts: nil,
        features: nil,
        uninterpreted_option: [],
        __pb_extensions__: %{},
        __unknown_fields__: [
          {870_012, 2,
           <<10, 163, 1, 10, 14, 99, 111, 109, 46, 97, 99, 109, 101, 46, 117, 115, 101, 114, 115, 18, 14, 117, 115, 101,
             114, 95, 110, 111, 116, 95, 102, 111, 117, 110, 100, 26, 32, 84, 104, 101, 32, 114, 101, 113, 117, 101,
             115, 116, 101, 100, 32, 117, 115, 101, 114, 32, 119, 97, 115, 32, 110, 111, 116, 32, 102, 111, 117, 110,
             100, 32, 5, 40, 2, 50, 44, 10, 27, 104, 116, 116, 112, 115, 58, 47, 47, 100, 111, 99, 115, 46, 97, 99, 109,
             101, 46, 99, 111, 109, 47, 117, 115, 101, 114, 115, 18, 13, 85, 115, 101, 114, 32, 65, 80, 73, 32, 68, 111,
             99, 115, 58, 18, 10, 8, 114, 101, 115, 111, 117, 114, 99, 101, 18, 4, 117, 115, 101, 114, 24, 2, 58, 25,
             10, 11, 116, 101, 110, 97, 110, 116, 95, 107, 105, 110, 100, 18, 8, 105, 110, 116, 101, 114, 110, 97, 108,
             24, 1>>}
        ]
      },
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:user_id, 1, type: :string, json_name: "userId", deprecated: false)
  field(:internal_trace, 2, type: :string, json_name: "internalTrace")
  field(:service, 3, type: :string, deprecated: false)
  field(:region, 4, type: :string, deprecated: false)
end

defmodule Acme.Test.V1.InternalServerError do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.InternalServerError",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "InternalServerError",
      field: [],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: %Google.Protobuf.MessageOptions{
        message_set_wire_format: false,
        no_standard_descriptor_accessor: false,
        deprecated: false,
        map_entry: nil,
        deprecated_legacy_json_field_conflicts: nil,
        features: nil,
        uninterpreted_option: [],
        __pb_extensions__: %{},
        __unknown_fields__: [
          {870_012, 2,
           <<10, 79, 10, 15, 99, 111, 109, 46, 97, 99, 109, 101, 46, 115, 121, 115, 116, 101, 109, 18, 21, 105, 110,
             116, 101, 114, 110, 97, 108, 95, 115, 101, 114, 118, 101, 114, 95, 101, 114, 114, 111, 114, 26, 33, 65,
             110, 32, 105, 110, 116, 101, 114, 110, 97, 108, 32, 115, 101, 114, 118, 101, 114, 32, 101, 114, 114, 111,
             114, 32, 111, 99, 99, 117, 114, 114, 101, 100, 32, 13, 40, 1>>}
        ]
      },
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end
end

defmodule Acme.Test.V1.MissingMetadataVisibilityError do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.MissingMetadataVisibilityError",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "MissingMetadataVisibilityError",
      field: [],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: %Google.Protobuf.MessageOptions{
        message_set_wire_format: false,
        no_standard_descriptor_accessor: false,
        deprecated: false,
        map_entry: nil,
        deprecated_legacy_json_field_conflicts: nil,
        features: nil,
        uninterpreted_option: [],
        __pb_extensions__: %{},
        __unknown_fields__: [
          {870_012, 2,
           <<10, 105, 10, 14, 99, 111, 109, 46, 97, 99, 109, 101, 46, 117, 115, 101, 114, 115, 18, 27, 109, 105, 115,
             115, 105, 110, 103, 95, 109, 101, 116, 97, 100, 97, 116, 97, 95, 118, 105, 115, 105, 98, 105, 108, 105,
             116, 121, 26, 36, 84, 104, 105, 115, 32, 104, 97, 115, 32, 109, 101, 116, 97, 100, 97, 116, 97, 32, 119,
             105, 116, 104, 111, 117, 116, 32, 118, 105, 115, 105, 98, 105, 108, 105, 116, 121, 32, 3, 40, 2, 58, 16,
             10, 8, 114, 101, 115, 111, 117, 114, 99, 101, 18, 4, 117, 115, 101, 114>>}
        ]
      },
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end
end

defmodule Acme.Test.V1.MissingDomainError do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.MissingDomainError",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "MissingDomainError",
      field: [],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: %Google.Protobuf.MessageOptions{
        message_set_wire_format: false,
        no_standard_descriptor_accessor: false,
        deprecated: false,
        map_entry: nil,
        deprecated_legacy_json_field_conflicts: nil,
        features: nil,
        uninterpreted_option: [],
        __pb_extensions__: %{},
        __unknown_fields__: [
          {870_012, 2,
           <<10, 38, 18, 14, 109, 105, 115, 115, 105, 110, 103, 95, 100, 111, 109, 97, 105, 110, 26, 18, 84, 104, 105,
             115, 32, 104, 97, 115, 32, 110, 111, 32, 100, 111, 109, 97, 105, 110, 32, 2>>}
        ]
      },
      oneof_decl: [],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end
end

defmodule Acme.Test.V1.NoExtensionMessage do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.NoExtensionMessage",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "NoExtensionMessage",
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

  field(:value, 1, type: :string)
end

defmodule Acme.Test.V1.NonStringFieldError do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.NonStringFieldError",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "NonStringFieldError",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "retry_count",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_INT32,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "retryCount",
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

  field(:retry_count, 1, type: :int32, json_name: "retryCount")
end
