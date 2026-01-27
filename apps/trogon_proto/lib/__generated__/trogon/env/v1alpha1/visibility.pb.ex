defmodule TrogonProto.Env.V1Alpha1.Visibility do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "trogon.env.v1alpha1.Visibility",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "Visibility",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "VISIBILITY_UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "VISIBILITY_PLAINTEXT",
          number: 1,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "VISIBILITY_SECRET",
          number: 2,
          options: nil,
          __unknown_fields__: []
        }
      ],
      options: nil,
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  field(:VISIBILITY_UNSPECIFIED, 0)
  field(:VISIBILITY_PLAINTEXT, 1)
  field(:VISIBILITY_SECRET, 2)
end
