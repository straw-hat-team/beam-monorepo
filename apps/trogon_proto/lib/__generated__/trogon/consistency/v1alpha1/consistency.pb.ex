defmodule TrogonProto.Consistency.V1Alpha1.Consistency do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.consistency.v1alpha1.Consistency",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "Consistency",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "min_version",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.consistency.v1alpha1.MinVersion",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "minVersion",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "exact_version",
          extendee: nil,
          number: 2,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".trogon.consistency.v1alpha1.ExactVersion",
          default_value: nil,
          options: nil,
          oneof_index: 0,
          json_name: "exactVersion",
          proto3_optional: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "timeout_duration",
          extendee: nil,
          number: 3,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".google.protobuf.Duration",
          default_value: nil,
          options: nil,
          oneof_index: 1,
          json_name: "timeoutDuration",
          proto3_optional: true,
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "delay_duration",
          extendee: nil,
          number: 4,
          label: :LABEL_OPTIONAL,
          type: :TYPE_MESSAGE,
          type_name: ".google.protobuf.Duration",
          default_value: nil,
          options: nil,
          oneof_index: 2,
          json_name: "delayDuration",
          proto3_optional: true,
          __unknown_fields__: []
        }
      ],
      nested_type: [],
      enum_type: [],
      extension_range: [],
      extension: [],
      options: nil,
      oneof_decl: [
        %Google.Protobuf.OneofDescriptorProto{
          name: "requirement",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{
          name: "_timeout_duration",
          options: nil,
          __unknown_fields__: []
        },
        %Google.Protobuf.OneofDescriptorProto{
          name: "_delay_duration",
          options: nil,
          __unknown_fields__: []
        }
      ],
      reserved_range: [],
      reserved_name: [],
      __unknown_fields__: []
    }
  end

  oneof(:requirement, 0)

  field(:min_version, 1,
    type: TrogonProto.Consistency.V1Alpha1.MinVersion,
    json_name: "minVersion",
    oneof: 0
  )

  field(:exact_version, 2,
    type: TrogonProto.Consistency.V1Alpha1.ExactVersion,
    json_name: "exactVersion",
    oneof: 0
  )

  field(:timeout_duration, 3,
    proto3_optional: true,
    type: Google.Protobuf.Duration,
    json_name: "timeoutDuration"
  )

  field(:delay_duration, 4,
    proto3_optional: true,
    type: Google.Protobuf.Duration,
    json_name: "delayDuration"
  )
end

defmodule TrogonProto.Consistency.V1Alpha1.MinVersion do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.consistency.v1alpha1.MinVersion",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "MinVersion",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "version",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_INT64,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "version",
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

  field(:version, 1, type: :int64)
end

defmodule TrogonProto.Consistency.V1Alpha1.ExactVersion do
  @moduledoc false

  use Protobuf,
    full_name: "trogon.consistency.v1alpha1.ExactVersion",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  def descriptor do
    # credo:disable-for-next-line
    %Google.Protobuf.DescriptorProto{
      name: "ExactVersion",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "version",
          extendee: nil,
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_INT64,
          type_name: nil,
          default_value: nil,
          options: nil,
          oneof_index: nil,
          json_name: "version",
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

  field(:version, 1, type: :int64)
end
