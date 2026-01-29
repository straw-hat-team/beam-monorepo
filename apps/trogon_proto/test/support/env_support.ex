# Mock proto module for unsupported repeated field testing
defmodule Acme.Test.V1.TestUnsupported do
  @moduledoc false

  def descriptor do
    %Google.Protobuf.DescriptorProto{
      name: "TestUnsupported",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "database_url",
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 2, 8, 2>>}]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "tags",
          number: 2,
          label: :LABEL_REPEATED,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 2, 8, 1>>}]
          },
          __unknown_fields__: []
        }
      ],
      __unknown_fields__: []
    }
  end
end

# Use the generated proto with all supported field types
defmodule Trogon.Proto.EnvTestSupport.AllTypesConfig do
  @moduledoc """
  Test support for Trogon.Proto.Env macro with all supported data types.
  Uses the generated Acme.Test.V1.TestConfig proto.
  """

  use Trogon.Proto.Env, message: Acme.Test.V1.TestConfig
end

# Mock unsupported test config with repeated field for testing validation warnings
defmodule Trogon.Proto.EnvTestSupport.ConfigWithUnsupported do
  @moduledoc "Config with unsupported repeated field - tests validation warnings"

  use Trogon.Proto.Env, message: Acme.Test.V1.TestUnsupported
end

# Mock proto module for testing repeated fields with split_delimiter
defmodule Acme.Test.V1.TestRepeated do
  @moduledoc false

  def descriptor do
    %Google.Protobuf.DescriptorProto{
      name: "TestRepeated",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "database_url",
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 2, 8, 2>>}]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "tags",
          number: 2,
          label: :LABEL_REPEATED,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 6, 8, 1, 34, 2, 44, 32>>}]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "port_list",
          number: 3,
          label: :LABEL_REPEATED,
          type: :TYPE_INT32,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 6, 8, 1, 34, 2, 44, 32>>}]
          },
          __unknown_fields__: []
        }
      ],
      __unknown_fields__: []
    }
  end
end

# Test config with repeated fields that have split_delimiter
defmodule Trogon.Proto.EnvTestSupport.ConfigWithRepeated do
  @moduledoc "Config with repeated fields using split_delimiter"

  use Trogon.Proto.Env, message: Acme.Test.V1.TestRepeated
end

# Mock proto module for testing trim with unicode_whitespace
defmodule Acme.Test.V1.TestTrimUnicode do
  @moduledoc false

  def descriptor do
    %Google.Protobuf.DescriptorProto{
      name: "TestTrimUnicode",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "database_url",
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 2, 8, 2>>}]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "tags",
          number: 2,
          label: :LABEL_REPEATED,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 10, 8, 1, 34, 2, 44, 32, 42, 2, 10, 0>>}]
          },
          __unknown_fields__: []
        }
      ],
      __unknown_fields__: []
    }
  end
end

defmodule Trogon.Proto.EnvTestSupport.ConfigWithTrimUnicode do
  @moduledoc "Config with repeated fields using split_delimiter and unicode trim"

  use Trogon.Proto.Env, message: Acme.Test.V1.TestTrimUnicode
end

# Mock proto module for testing trim with custom chars
defmodule Acme.Test.V1.TestTrimCustom do
  @moduledoc false

  def descriptor do
    %Google.Protobuf.DescriptorProto{
      name: "TestTrimCustom",
      field: [
        %Google.Protobuf.FieldDescriptorProto{
          name: "database_url",
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 2, 8, 2>>}]
          },
          __unknown_fields__: []
        },
        %Google.Protobuf.FieldDescriptorProto{
          name: "tags",
          number: 2,
          label: :LABEL_REPEATED,
          type: :TYPE_STRING,
          options: %Google.Protobuf.FieldOptions{
            __unknown_fields__: [{870_003, 2, <<10, 11, 8, 1, 34, 2, 44, 32, 42, 3, 18, 1, 42>>}]
          },
          __unknown_fields__: []
        }
      ],
      __unknown_fields__: []
    }
  end
end

defmodule Trogon.Proto.EnvTestSupport.ConfigWithTrimCustom do
  @moduledoc "Config with repeated fields using split_delimiter and custom chars trim"

  use Trogon.Proto.Env, message: Acme.Test.V1.TestTrimCustom
end
