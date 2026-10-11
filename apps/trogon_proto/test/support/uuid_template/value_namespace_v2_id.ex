defmodule Trogon.Proto.TestSupport.UuidTemplate.ValueNamespaceV2Id do
  @moduledoc "V2 overrides with value-level namespace."

  alias Acme.ValueNamespace.V1.ValueNamespaceId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  use UuidTemplate,
    enum: ValueNamespaceId.IdentityVersion,
    version: :IDENTITY_VERSION_V2
end
