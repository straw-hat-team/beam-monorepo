defmodule Trogon.Commanded.TestSupport.CommandRouterExample.ObjectTypeEnum do
  @moduledoc false

  use Trogon.Commanded.Enum,
    proto: Acme.Type.V1.ObjectType
end
