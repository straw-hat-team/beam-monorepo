defmodule Acme.Test.V1.TestEnumInvalidDefault do
  @moduledoc false

  use Protobuf,
    full_name: "acme.test.v1.TestEnumInvalidDefault",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "TestEnumInvalidDefault",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "log_level",
          extendee: nil,
          number: 1,
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
            __unknown_fields__: [{870_003, 2, <<10, 9, 8, 1, 18, 5, 100, 101, 98, 117, 103>>}]
          },
          oneof_index: nil,
          json_name: "logLevel",
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

  field :log_level, 1,
    type: Acme.Test.V1.LogLevel,
    json_name: "logLevel",
    enum: true,
    deprecated: false
end
