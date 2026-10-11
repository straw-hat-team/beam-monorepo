defmodule Trogon.Proto.TestSupport.UuidTemplate.ValueNamespaceV1Id do
  @moduledoc "V1 uses enum-level namespace (no value-level override)."

  alias Acme.ValueNamespace.V1.ValueNamespaceId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  use UuidTemplate,
    enum: ValueNamespaceId.IdentityVersion,
    version: :IDENTITY_VERSION_V1
end
