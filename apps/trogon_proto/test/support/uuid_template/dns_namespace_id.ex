defmodule Trogon.Proto.TestSupport.UuidTemplate.DnsNamespaceId do
  @moduledoc "DNS namespace example."

  alias Acme.Order.V1.OrderId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  use UuidTemplate,
    enum: OrderId.IdentityVersion,
    version: :IDENTITY_VERSION_V1
end
