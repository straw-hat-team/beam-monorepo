defmodule Trogon.Proto.TestSupport.FutureSchema do
  @moduledoc """
  Message doubles that stand in for annotations written against a newer
  `trogon.env.v1alpha1` than this package is generated from.

  buf cannot produce such a fixture, because the test protos import the very
  `options.proto` the package is generated from, so the annotation bytes are
  assembled by hand here.
  """

  alias Google.Protobuf.DescriptorProto
  alias Google.Protobuf.FieldDescriptorProto
  alias Google.Protobuf.FieldOptions
  alias TrogonProto.Env.V1Alpha1.EnvVarOption

  @extension_tag 870_003

  # Field 9, varint wire type, value 1. No release of trogon.env.v1alpha1
  # assigns it, so a decoder generated from this schema preserves it as an
  # unknown field instead of reading it.
  @future_field <<72, 1>>

  def descriptor(name, extension_binary) do
    %DescriptorProto{
      name: name,
      field: [
        %FieldDescriptorProto{
          name: "database_url",
          number: 1,
          label: :LABEL_OPTIONAL,
          type: :TYPE_STRING,
          json_name: "databaseUrl",
          options: %FieldOptions{__unknown_fields__: [{@extension_tag, 2, extension_binary}]}
        }
      ]
    }
  end

  def message_props do
    %{field_props: %{1 => %{repeated?: false, type: :string}}}
  end

  def supported_annotation do
    embed_env_var(EnvVarOption.encode(%EnvVarOption{visibility: :VISIBILITY_PLAINTEXT}))
  end

  def annotation_with_future_option do
    supported_annotation() <> @future_field
  end

  def annotation_with_future_env_var_option do
    embed_env_var(EnvVarOption.encode(%EnvVarOption{visibility: :VISIBILITY_PLAINTEXT}) <> @future_field)
  end

  def annotation_with_future_visibility do
    embed_env_var(<<8, 7>>)
  end

  defp embed_env_var(binary), do: <<10, byte_size(binary)>> <> binary
end

defmodule Trogon.Proto.TestSupport.FutureSchema.SupportedAnnotation do
  @moduledoc false

  alias Trogon.Proto.TestSupport.FutureSchema

  defstruct [:database_url]

  @type t :: %__MODULE__{database_url: String.t() | nil}

  def descriptor, do: FutureSchema.descriptor("SupportedAnnotation", FutureSchema.supported_annotation())
  def __message_props__, do: FutureSchema.message_props()
end

defmodule Trogon.Proto.TestSupport.FutureSchema.FutureOption do
  @moduledoc false

  alias Trogon.Proto.TestSupport.FutureSchema

  defstruct [:database_url]

  @type t :: %__MODULE__{database_url: String.t() | nil}

  def descriptor, do: FutureSchema.descriptor("FutureOption", FutureSchema.annotation_with_future_option())
  def __message_props__, do: FutureSchema.message_props()
end

defmodule Trogon.Proto.TestSupport.FutureSchema.FutureEnvVarOption do
  @moduledoc false

  alias Trogon.Proto.TestSupport.FutureSchema

  defstruct [:database_url]

  @type t :: %__MODULE__{database_url: String.t() | nil}

  def descriptor,
    do: FutureSchema.descriptor("FutureEnvVarOption", FutureSchema.annotation_with_future_env_var_option())

  def __message_props__, do: FutureSchema.message_props()
end

defmodule Trogon.Proto.TestSupport.FutureSchema.FutureVisibility do
  @moduledoc false

  alias Trogon.Proto.TestSupport.FutureSchema

  defstruct [:database_url]

  @type t :: %__MODULE__{database_url: String.t() | nil}

  def descriptor, do: FutureSchema.descriptor("FutureVisibility", FutureSchema.annotation_with_future_visibility())
  def __message_props__, do: FutureSchema.message_props()
end
