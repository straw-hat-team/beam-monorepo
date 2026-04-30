defmodule Trogon.ObjectId.TestSupport do
  @moduledoc false

  defmodule UserId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "user"
  end

  defmodule OrderId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "order"
  end

  defmodule AccountId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "account"
  end

  defmodule CustomSeparatorId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "custom", separator: "#"
  end

  defmodule FullStorageId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "full", storage_format: :full
  end

  defmodule DropPrefixId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "drop", storage_format: :drop_prefix
  end

  defmodule TypeWithSeparatorId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "my_user", separator: "_"
  end

  defmodule SimpleTypeId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "myuser"
  end

  defmodule DashTypeId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "my-user", separator: "_"
  end

  defmodule JsonDropPrefixId do
    @moduledoc false
    use Trogon.ObjectId,
      object_type: "jsondrop",
      storage_format: :full,
      json_format: :drop_prefix
  end

  defmodule StorageDropJsonFullId do
    @moduledoc false
    use Trogon.ObjectId,
      object_type: "mixed",
      storage_format: :drop_prefix,
      json_format: :full
  end

  defmodule TenantId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "tenant"
  end

  defmodule SystemId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "system"
  end

  defmodule ServiceId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "service"
  end

  defmodule ContextId do
    @moduledoc false
    use Trogon.UnionObjectId, types: [TenantId, SystemId]
  end

  defmodule PrincipalId do
    @moduledoc false
    use Trogon.UnionObjectId, types: [TenantId, SystemId, ServiceId]
  end

  defmodule AmbiguousPrefixIdA do
    @moduledoc false
    use Trogon.ObjectId, object_type: "a", separator: "bc_"
  end

  defmodule AmbiguousPrefixIdB do
    @moduledoc false
    use Trogon.ObjectId, object_type: "abc", separator: "_"
  end

  defmodule UuidFormatId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "uuid", validate: :uuid
  end

  defmodule IntegerFormatId do
    @moduledoc false
    use Trogon.ObjectId, object_type: "int", validate: :integer
  end

  defmodule UuidDropPrefixId do
    @moduledoc false
    use Trogon.ObjectId,
      object_type: "uuiddrop",
      storage_format: :drop_prefix,
      validate: :uuid
  end

  defmodule ProtoTicketId do
    @moduledoc false
    use Trogon.ObjectId,
      proto: {Acme.Type.V1.ObjectType, :OBJECT_TYPE_TICKET}
  end

  defmodule ProtoWorkspaceId do
    @moduledoc false
    use Trogon.ObjectId,
      proto: {Acme.Type.V1.ObjectType, :OBJECT_TYPE_WORKSPACE},
      storage_format: :drop_prefix
  end

  defmodule CustomValidator do
    @moduledoc false

    def check(value) do
      if String.starts_with?(value, "valid-") do
        :ok
      else
        {:error, :invalid_custom_format}
      end
    end
  end

  defmodule CustomFormatId do
    @moduledoc false
    use Trogon.ObjectId,
      object_type: "custom_fmt",
      validate: {Trogon.ObjectId.TestSupport.CustomValidator, :check}
  end

  defmodule ValidatedUnionId do
    @moduledoc false
    use Trogon.UnionObjectId, types: [UuidFormatId, TenantId]
  end
end
