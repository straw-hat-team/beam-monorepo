defmodule TrogonProto.Error.V1Alpha1.PbExtension do
  use Protobuf, protoc_gen_elixir_version: "0.16.0"

  extend(Google.Protobuf.MessageOptions, :message, 870_012,
    optional: true,
    type: TrogonProto.Error.V1Alpha1.MessageOptions
  )

  extend(Google.Protobuf.FieldOptions, :field, 870_013,
    optional: true,
    type: TrogonProto.Error.V1Alpha1.FieldOptions
  )
end
