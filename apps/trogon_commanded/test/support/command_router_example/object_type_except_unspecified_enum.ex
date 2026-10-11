defmodule Trogon.Commanded.TestSupport.CommandRouterExample.ObjectTypeExceptUnspecifiedEnum do
  @moduledoc false

  use Trogon.Commanded.Enum,
    proto: {Acme.Type.V1.ObjectType, except: [:OBJECT_TYPE_UNSPECIFIED]}
end
