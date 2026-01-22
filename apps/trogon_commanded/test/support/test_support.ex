defmodule TestSupport do
  @moduledoc false

  defmodule TransferableMoney do
    @moduledoc false
    use Trogon.Commanded.ValueObject

    embedded_schema do
      field :amount, :integer
      field :currency, Ecto.Enum, values: [:USD]
    end

    def validate(changeset, _attrs) do
      changeset
      |> Changeset.validate_number(:amount, greater_than: 0)
    end
  end

  defmodule MyValueOject do
    @moduledoc false
    use Trogon.Commanded.ValueObject

    @enforce_keys [:title, :amount]
    embedded_schema do
      field :title, :string
      field :amount, :integer
    end

    def changeset(message, attrs) do
      message
      |> ValueObject.changeset(attrs)
      |> Changeset.validate_number(:amount, greater_than: 0)
    end
  end

  defmodule AccountNumber do
    @moduledoc false
    use Trogon.Commanded.ValueObject

    embedded_schema do
      field :branch, :string
      field :account_number, :string
    end
  end

  defmodule MessageOne do
    @moduledoc false

    use Trogon.Commanded.ValueObject

    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageTwo do
    @moduledoc false

    use Trogon.Commanded.ValueObject

    @enforce_keys [:title]
    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageThree do
    @moduledoc false

    use Trogon.Commanded.ValueObject

    @enforce_keys [:target]
    embedded_schema do
      embeds_one(:target, MessageOne)
    end
  end

  defmodule MessageFour do
    @moduledoc false

    use Trogon.Commanded.ValueObject

    @enforce_keys [:targets]
    embedded_schema do
      embeds_many(:targets, MessageThree)
    end
  end

  defmodule MyEntityOne do
    @moduledoc false

    use Trogon.Commanded.Entity, identifier: :uuid

    @enforce_keys [:name]
    embedded_schema do
      field :name, :string
    end
  end

  defmodule BankAccountEntity do
    @moduledoc false

    use Trogon.Commanded.Entity, identifier: {:uuid, AccountNumber}

    @enforce_keys [:type]
    embedded_schema do
      field :type, Ecto.Enum, values: [:DEPOSITORY]
    end
  end

  defmodule MyCommandOne do
    @moduledoc false

    use Trogon.Commanded.Command, aggregate_identifier: :uuid

    embedded_schema do
    end
  end

  defmodule OpenDepositAccountCommand do
    @moduledoc false

    use Trogon.Commanded.Command, aggregate_identifier: {:uuid, AccountNumber}

    @enforce_keys [:type]
    embedded_schema do
      field :type, Ecto.Enum, values: [:DEPOSITORY]
    end
  end

  defmodule MyEventOne do
    @moduledoc false

    use Trogon.Commanded.Event, aggregate_identifier: :uuid

    embedded_schema do
      field :name, :string
    end
  end

  defmodule DepositAccountOpened do
    @moduledoc false

    use Trogon.Commanded.Event, aggregate_identifier: {:uuid, AccountNumber}

    embedded_schema do
      field :type, Ecto.Enum, values: [:DEPOSITORY]
    end
  end

  defmodule MyEventTwo do
    @moduledoc false

    use Trogon.Commanded.Event, aggregate_identifier: :uuid

    embedded_schema do
      field :name, :string
    end
  end

  defmodule MyAggregateOne do
    @moduledoc false

    use Trogon.Commanded.Aggregate, identifier: :uuid

    embedded_schema do
      field :name, :string
    end

    @impl Trogon.Commanded.Aggregate
    def apply(aggregate, %MyEventOne{} = event) do
      aggregate
      |> Map.put(:uuid, event.uuid)
      |> Map.put(:name, event.name)
    end
  end

  defmodule DefaultApp do
    @moduledoc false
    use Commanded.Application,
      otp_app: :trogon_commanded,
      event_store: [
        adapter: Commanded.EventStore.Adapters.InMemory,
        serializer: Commanded.Serialization.JsonSerializer
      ],
      pubsub: :local,
      registry: :local
  end

  defmodule EmailContent do
    @moduledoc false
    use Trogon.Commanded.ValueObject

    @enforce_keys [:subject, :body]
    embedded_schema do
      field :type, :string, default: "email"
      field :subject, :string
      field :body, :string
    end
  end

  defmodule SmsContent do
    @moduledoc false
    use Trogon.Commanded.ValueObject

    @enforce_keys [:message, :phone]
    embedded_schema do
      field :type, :string, default: "sms"
      field :message, :string
      field :phone, :string
    end
  end

  defmodule NotificationWithPolymorphicEmbed do
    @moduledoc false
    use Trogon.Commanded.ValueObject

    @enforce_keys [:title, :content]
    embedded_schema do
      field :title, :string

      polymorphic_embeds_one :content,
        types: [
          email: TestSupport.EmailContent,
          sms: TestSupport.SmsContent
        ],
        on_type_not_found: :raise,
        on_replace: :update
    end
  end

  defmodule MessageWithMultiplePolymorphicEmbeds do
    @moduledoc false
    use Trogon.Commanded.ValueObject

    @enforce_keys [:title, :contents]
    embedded_schema do
      field :title, :string

      polymorphic_embeds_many :contents,
        types: [
          email: TestSupport.EmailContent,
          sms: TestSupport.SmsContent
        ],
        on_type_not_found: :raise,
        on_replace: :delete
    end
  end

  def errors_on(changeset) do
    # Use PolymorphicEmbed's traverse_errors for better polymorphic embed support
    PolymorphicEmbed.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defmodule UserId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "user"
  end

  defmodule OrderId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "order"
  end

  defmodule AccountId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "account"
  end

  defmodule CustomSeparatorId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "custom", separator: "#"
  end

  defmodule FullStorageId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "full", storage_format: :full
  end

  defmodule DropPrefixId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "drop", storage_format: :drop_prefix
  end

  defmodule TypeWithSeparatorId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "my_user", separator: "_"
  end

  defmodule SimpleTypeId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "myuser"
  end

  defmodule DashTypeId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "my-user", separator: "_"
  end

  defmodule JsonDropPrefixId do
    @moduledoc false
    use Trogon.Commanded.ObjectId,
      object_type: "jsondrop",
      storage_format: :full,
      json_format: :drop_prefix
  end

  defmodule StorageDropJsonFullId do
    @moduledoc false
    use Trogon.Commanded.ObjectId,
      object_type: "mixed",
      storage_format: :drop_prefix,
      json_format: :full
  end

  defmodule TenantId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "tenant"
  end

  defmodule SystemId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "system"
  end

  defmodule ServiceId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "service"
  end

  defmodule ContextId do
    @moduledoc false
    use Trogon.Commanded.UnionObjectId, types: [TenantId, SystemId]
  end

  defmodule PrincipalId do
    @moduledoc false
    use Trogon.Commanded.UnionObjectId, types: [TenantId, SystemId, ServiceId]
  end

  defmodule AmbiguousPrefixIdA do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "a", separator: "bc_"
  end

  defmodule AmbiguousPrefixIdB do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "abc", separator: "_"
  end

  # Format validation test modules
  defmodule UuidFormatId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "uuid", validate: :uuid
  end

  defmodule IntegerFormatId do
    @moduledoc false
    use Trogon.Commanded.ObjectId, object_type: "int", validate: :integer
  end

  defmodule UuidDropPrefixId do
    @moduledoc false
    use Trogon.Commanded.ObjectId,
      object_type: "uuiddrop",
      storage_format: :drop_prefix,
      validate: :uuid
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
    use Trogon.Commanded.ObjectId,
      object_type: "custom_fmt",
      validate: {TestSupport.CustomValidator, :check}
  end
end
