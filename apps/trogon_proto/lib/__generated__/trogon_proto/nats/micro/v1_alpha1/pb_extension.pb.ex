defmodule TrogonProto.Nats.Micro.V1Alpha1.PbExtension do
  use Protobuf, protoc_gen_elixir_version: "0.16.0"

  extend(Google.Protobuf.ServiceOptions, :service, 870_014,
    optional: true,
    type: TrogonProto.Nats.Micro.V1Alpha1.ServiceOptions
  )

  extend(Google.Protobuf.MethodOptions, :method, 870_015,
    optional: true,
    type: TrogonProto.Nats.Micro.V1Alpha1.MethodOptions
  )
end
