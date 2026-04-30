defmodule TrogonProto.Consistency.V1Alpha1.Consistency do
  @moduledoc """
  Configuration for read-your-writes consistency guarantees in eventual consistency systems.

  Used in query operations to wait for projections/read models to catch up to a specific version
  after a write operation. This enables clients to immediately read their own writes despite
  projection lag in CQRS/Event Sourcing architectures.

  ## Consistency Modes

  ### MinVersion (Recommended - Read-Your-Writes)
  Waits for projection to reach AT LEAST the specified version. Will use newer data if available.
  Use this after mutations to ensure you can immediately read what you just wrote.

  ### ExactVersion (Strict - Reproducible Snapshots)
  Waits for projection to reach EXACTLY the specified version. Rejects if version is newer.
  Use this only when you need reproducible queries at a specific point-in-time (audits, reports).

  ## Usage Pattern

  1. Client performs mutation (e.g., CreateOrder, UpdateInventory)
  2. Server returns stream_version (e.g., version 5)
  3. Client immediately queries with Consistency:
     - min_version { version: 5 }  (recommended - read-your-writes)
     - exact_version { version: 5 }  (strict - reproducible snapshot)
  4. Server retries query until projection reaches version or timeout

  ## Example

  ```protobuf
  // Mutation response
  message CreateOrderResponse {
    string order_id = 1;
    uint64 stream_version = 2;  // Returns: 5
  }

  // Read-your-writes (recommended)
  message GetOrderRequest {
    string order_id = 1;
    trogon.consistency.v1alpha1.Consistency consistency = 2;
  }

  GetOrderRequest {
    order_id: "order-123",
    consistency: {
      min_version: { version: 5 },
      timeout_duration: "1s",
      delay_duration: "100ms"
    }
  }
  ```

  ## Server Implementation Guidelines

  Servers should:
  - Enforce reasonable timeout limits (e.g., default 1s, max 5s)
  - Enforce reasonable delay limits (e.g., default 100ms, max 500ms)
  - Return unavailable status on timeout with appropriate error metadata
  - Return failed precondition status on snapshot expired (ExactVersion only)
  - Log when clamping client-provided values

  ## Reference

  Inspired by SpiceDB's Consistency patterns (at_least_as_fresh and at_exact_snapshot modes).
  See: https://authzed.com/docs/spicedb/concepts/consistency
  """

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
  @moduledoc """
  Wait for projection to be at least as fresh as the specified version.
  """

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
  @moduledoc """
  Wait for projection to reach exactly the specified version (strict snapshot).
  """

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
