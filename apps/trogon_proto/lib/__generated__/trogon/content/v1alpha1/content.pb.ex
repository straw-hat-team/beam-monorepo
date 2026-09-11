defmodule TrogonProto.Content.V1Alpha1.Content do
  @moduledoc """
  Content is a self-describing blob whose interpretation is carried by its
  media type.

  Use Content for "give me whatever" fields where the producer and consumer
  negotiate the concrete encoding out of band, and protobuf only needs to
  transport the typed bytes. Prefer explicit domain messages when the schema
  is known at design time; reach for Content only when the schema is open or
  pluggable.

  Example usage:

    import "trogon/content/v1alpha1/content.proto";

    message PublishRequest {
      string subject = 1;
      trogon.content.v1alpha1.Content body = 2;
    }
  """

  use Protobuf,
    full_name: "trogon.content.v1alpha1.Content",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Content",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "content_type",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "contentType",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "data",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_BYTES,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "data",
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

  field(:content_type, 1, type: :string, json_name: "contentType")
  field(:data, 2, type: :bytes)
end
