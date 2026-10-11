defmodule TrogonProto.Error.V1Alpha1.Visibility do
  @moduledoc """
  Visibility controls who can see a given error metadata field.

  Visibility is an exposure contract for shared descriptors. It is not a
  secrecy boundary for data encoded in proto annotations: anyone with the
  descriptor can read those keys and values. Internal-only metadata belongs in
  runtime enrichment, observability pipelines, or internal-only overlays.

  Code generators should reject UNSPECIFIED for emitted error details.
  """

  use Protobuf,
    enum: true,
    full_name: "trogon.error.v1alpha1.Visibility",
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
          name: "VISIBILITY_PRIVATE",
          number: 1,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "VISIBILITY_PUBLIC",
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
  field(:VISIBILITY_PRIVATE, 1)
  field(:VISIBILITY_PUBLIC, 2)
end
