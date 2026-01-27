defmodule TrogonProto.Env.V1Alpha1.PbExtension do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.16.0"

  extend(Google.Protobuf.FieldOptions, :field, 870_003,
    optional: true,
    type: TrogonProto.Env.V1Alpha1.FieldOptions
  )
end
