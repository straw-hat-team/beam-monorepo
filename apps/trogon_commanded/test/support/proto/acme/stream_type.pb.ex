defmodule Acme.Type.V1.StreamType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "acme.type.v1.StreamType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "StreamType",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "STREAM_TYPE_UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "STREAM_TYPE_BANK_ACCOUNT",
          number: 1,
          options: %Google.Protobuf.EnumValueOptions{
            deprecated: false,
            features: nil,
            debug_redact: false,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [{870_011, 2, "\n\fbank-account"}]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "STREAM_TYPE_ORDER",
          number: 2,
          options: %Google.Protobuf.EnumValueOptions{
            deprecated: false,
            features: nil,
            debug_redact: false,
            feature_support: nil,
            uninterpreted_option: [],
            __pb_extensions__: %{},
            __unknown_fields__: [{870_011, 2, <<10, 5, 111, 114, 100, 101, 114, 18, 1, 35>>}]
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

  field :STREAM_TYPE_UNSPECIFIED, 0
  field :STREAM_TYPE_BANK_ACCOUNT, 1
  field :STREAM_TYPE_ORDER, 2
end
