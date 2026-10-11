defmodule Trogon.Proto.TestSupport.UuidTemplate.UrlNamespaceId do
  @moduledoc "URL namespace example."

  alias Acme.Resource.V1.ResourceId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  use UuidTemplate,
    enum: ResourceId.IdentityVersion,
    version: :IDENTITY_VERSION_V1
end
