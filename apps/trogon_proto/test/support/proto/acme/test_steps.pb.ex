defmodule Acme.Test.V1.TestSteps do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.TestSteps",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "TestSteps",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "token_signing_key",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_BYTES,
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
              {870_003, 2,
               <<10, 30, 8, 2, 50, 4, 18, 2, 10, 0, 50, 20, 26, 18, 10, 6, 10, 4, 8, 1, 16, 1, 10, 2, 26, 0, 18, 4, 10,
                 2, 8, 32>>}
            ]
          },
          oneof_index: nil,
          json_name: "tokenSigningKey",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "signature",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_BYTES,
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
            __unknown_fields__: [{870_003, 2, <<10, 10, 8, 2, 50, 6, 26, 4, 10, 2, 18, 0>>}]
          },
          oneof_index: nil,
          json_name: "signature",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "session_id",
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
              {870_003, 2, <<10, 20, 8, 1, 50, 4, 18, 2, 10, 0, 50, 10, 34, 8, 10, 6, 18, 4, 8, 8, 16, 16>>}
            ]
          },
          oneof_index: nil,
          json_name: "sessionId",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "port_list",
          extendee: nil,
          number: 4,
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
            __unknown_fields__: [
              {870_003, 2, <<10, 15, 8, 1, 50, 5, 10, 3, 10, 1, 44, 50, 4, 18, 2, 10, 0>>}
            ]
          },
          oneof_index: nil,
          json_name: "portList",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "tags",
          extendee: nil,
          number: 5,
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
            __unknown_fields__: [
              {870_003, 2, <<10, 22, 8, 1, 50, 5, 10, 3, 10, 1, 44, 50, 4, 18, 2, 10, 0, 50, 5, 18, 3, 18, 1, 42>>}
            ]
          },
          oneof_index: nil,
          json_name: "tags",
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

  field(:token_signing_key, 1, type: :bytes, json_name: "tokenSigningKey", deprecated: false)
  field(:signature, 2, type: :bytes, deprecated: false)
  field(:session_id, 3, type: :string, json_name: "sessionId", deprecated: false)
  field(:port_list, 4, repeated: true, type: :int32, json_name: "portList", deprecated: false)
  field(:tags, 5, repeated: true, type: :string, deprecated: false)
end

defmodule Acme.Test.V1.TestStepsDefault do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.TestStepsDefault",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "TestStepsDefault",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "token_signing_key",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_BYTES,
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
              {870_003, 2,
               <<10, 76, 8, 2, 18, 44, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65,
                 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 61, 50, 4,
                 18, 2, 10, 0, 50, 20, 26, 18, 10, 6, 10, 4, 8, 1, 16, 1, 10, 2, 26, 0, 18, 4, 10, 2, 8, 32>>}
            ]
          },
          oneof_index: nil,
          json_name: "tokenSigningKey",
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
            __unknown_fields__: [
              {870_003, 2, <<10, 21, 8, 1, 18, 4, 97, 44, 32, 98, 50, 5, 10, 3, 10, 1, 44, 50, 4, 18, 2, 10, 0>>}
            ]
          },
          oneof_index: nil,
          json_name: "tags",
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

  field(:token_signing_key, 1, type: :bytes, json_name: "tokenSigningKey", deprecated: false)
  field(:tags, 2, repeated: true, type: :string, deprecated: false)
end

defmodule Acme.Test.V1.TestStepsUrlSafe do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.TestStepsUrlSafe",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "TestStepsUrlSafe",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "token_signing_key",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_BYTES,
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
              {870_003, 2, <<10, 22, 8, 2, 50, 18, 26, 16, 10, 6, 10, 4, 8, 2, 16, 2, 18, 6, 10, 4, 18, 2, 8, 16>>}
            ]
          },
          oneof_index: nil,
          json_name: "tokenSigningKey",
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

  field(:token_signing_key, 1, type: :bytes, json_name: "tokenSigningKey", deprecated: false)
end
