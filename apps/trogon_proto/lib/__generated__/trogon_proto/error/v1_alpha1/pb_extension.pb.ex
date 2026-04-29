defmodule TrogonProto.Error.V1Alpha1.PbExtension do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.16.0"

  extend(Google.Protobuf.MessageOptions, :message, 870_012,
    optional: true,
    type: TrogonProto.Error.V1Alpha1.MessageOptions
  )
end
