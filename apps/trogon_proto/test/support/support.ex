defmodule Trogon.Proto.TestSupport do
  @moduledoc """
  Test support modules using UuidTemplate with proto-generated enums.
  """

  alias Acme.Order.V1.OrderId
  alias Acme.Singleton.V1.SingletonId
  alias Acme.Resource.V1.ResourceId
  alias Acme.Entity.V1.EntityId
  alias Acme.ValueNamespace.V1.ValueNamespaceId
  alias Trogon.Proto.Uuid.V1.UuidTemplate

  defmodule AcmeOrderId do
    @moduledoc "Dynamic template with DNS namespace and multi-key template."
    use UuidTemplate,
      enum: OrderId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule StaticSingletonId do
    @moduledoc "Static template with no placeholders."
    use UuidTemplate,
      enum: SingletonId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule DnsNamespaceId do
    @moduledoc "DNS namespace example."
    use UuidTemplate,
      enum: OrderId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule UrlNamespaceId do
    @moduledoc "URL namespace example."
    use UuidTemplate,
      enum: ResourceId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule UuidNamespaceId do
    @moduledoc "Custom UUID namespace example."
    use UuidTemplate,
      enum: EntityId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  # Namespace resolution tests

  defmodule ValueNamespaceV1Id do
    @moduledoc "V1 uses enum-level namespace (no value-level override)."
    use UuidTemplate,
      enum: ValueNamespaceId.IdentityVersion,
      version: :IDENTITY_VERSION_V1
  end

  defmodule ValueNamespaceV2Id do
    @moduledoc "V2 overrides with value-level namespace."
    use UuidTemplate,
      enum: ValueNamespaceId.IdentityVersion,
      version: :IDENTITY_VERSION_V2
  end
end
