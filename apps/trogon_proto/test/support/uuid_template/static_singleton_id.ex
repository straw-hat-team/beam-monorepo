defmodule Trogon.Proto.TestSupport.UuidTemplate.StaticSingletonId do
  @moduledoc "Static template with no placeholders."

  alias Acme.Singleton.V1.SingletonId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  use UuidTemplate,
    enum: SingletonId.IdentityVersion,
    version: :IDENTITY_VERSION_V1
end
