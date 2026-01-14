defmodule TrogonProto.Uuid.V1.PbExtension do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.16.0"

  extend(Google.Protobuf.EnumOptions, :enum, 870_001,
    optional: true,
    type: TrogonProto.Uuid.V1.EnumOptions
  )

  extend(Google.Protobuf.EnumValueOptions, :enum_value, 870_002,
    optional: true,
    type: TrogonProto.Uuid.V1.EnumValueOptions,
    json_name: "enumValue"
  )
end
