defmodule TrogonProto.Stream.V1Alpha1.PbExtension do
  use Protobuf, protoc_gen_elixir_version: "0.16.0"

  extend(Google.Protobuf.EnumValueOptions, :enum_value, 870_011,
    optional: true,
    type: TrogonProto.Stream.V1Alpha1.EnumValueOptions,
    json_name: "enumValue"
  )
end
