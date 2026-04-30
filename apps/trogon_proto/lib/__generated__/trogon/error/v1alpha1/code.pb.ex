defmodule TrogonProto.Error.V1Alpha1.Code do
  @moduledoc """
  The canonical error codes for gRPC APIs.

  This enum mirrors the error values from `google.rpc.Code` so typed error
  templates can point at the canonical Google RPC error space without
  importing `google.rpc`.

  `OK` is intentionally omitted because this enum is used only for errors.

  Sometimes multiple error codes may apply. Services should return the most
  specific error code that applies. For example, prefer `OUT_OF_RANGE` over
  `FAILED_PRECONDITION` if both codes apply. Similarly prefer `NOT_FOUND` or
  `ALREADY_EXISTS` over `FAILED_PRECONDITION`.

  Source:
  https://github.com/googleapis/googleapis/blob/master/google/rpc/code.proto
  """

  use Protobuf,
    enum: true,
    full_name: "trogon.error.v1alpha1.Code",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.EnumDescriptorProto{
      name: "Code",
      value: [
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "UNSPECIFIED",
          number: 0,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "CANCELLED",
          number: 1,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "UNKNOWN",
          number: 2,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "INVALID_ARGUMENT",
          number: 3,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "DEADLINE_EXCEEDED",
          number: 4,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "NOT_FOUND",
          number: 5,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "ALREADY_EXISTS",
          number: 6,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "PERMISSION_DENIED",
          number: 7,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "UNAUTHENTICATED",
          number: 16,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "RESOURCE_EXHAUSTED",
          number: 8,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "FAILED_PRECONDITION",
          number: 9,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "ABORTED",
          number: 10,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "OUT_OF_RANGE",
          number: 11,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "UNIMPLEMENTED",
          number: 12,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "INTERNAL",
          number: 13,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "UNAVAILABLE",
          number: 14,
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.EnumValueDescriptorProto{
          name: "DATA_LOSS",
          number: 15,
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

  field :UNSPECIFIED, 0
  field :CANCELLED, 1
  field :UNKNOWN, 2
  field :INVALID_ARGUMENT, 3
  field :DEADLINE_EXCEEDED, 4
  field :NOT_FOUND, 5
  field :ALREADY_EXISTS, 6
  field :PERMISSION_DENIED, 7
  field :UNAUTHENTICATED, 16
  field :RESOURCE_EXHAUSTED, 8
  field :FAILED_PRECONDITION, 9
  field :ABORTED, 10
  field :OUT_OF_RANGE, 11
  field :UNIMPLEMENTED, 12
  field :INTERNAL, 13
  field :UNAVAILABLE, 14
  field :DATA_LOSS, 15
end
