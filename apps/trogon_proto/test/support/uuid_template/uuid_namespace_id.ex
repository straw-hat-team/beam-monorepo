defmodule Trogon.Proto.TestSupport.UuidTemplate.UuidNamespaceId do
  @moduledoc "Custom UUID namespace example."

  alias Acme.Entity.V1.EntityId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  use UuidTemplate,
    enum: EntityId.IdentityVersion,
    version: :IDENTITY_VERSION_V1
end
