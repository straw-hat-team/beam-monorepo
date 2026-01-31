defmodule Trogon.Proto.TestSupport.UuidTemplate.AcmeOrderId do
  @moduledoc "Dynamic template with DNS namespace and multi-key template."

  alias Acme.Order.V1.OrderId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  use UuidTemplate,
    enum: OrderId.IdentityVersion,
    version: :IDENTITY_VERSION_V1
end
