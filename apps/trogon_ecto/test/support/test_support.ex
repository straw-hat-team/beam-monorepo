defmodule Trogon.Ecto.TestSupport do
  @moduledoc false

  defmodule TransferableMoney do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :amount, :integer
      field :currency, Ecto.Enum, values: [:USD]
    end

    def validate(changeset, _attrs) do
      changeset
      |> Changeset.validate_number(:amount, greater_than: 0)
    end
  end

  defmodule MyValueObject do
    @moduledoc false
    use Trogon.Ecto.ValueObject

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

  defmodule MessageOne do
    @moduledoc false

    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageTwo do
    @moduledoc false

    use Trogon.Ecto.ValueObject

    @enforce_keys [:title]
    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageThree do
    @moduledoc false

    use Trogon.Ecto.ValueObject

    @enforce_keys [:target]
    embedded_schema do
      embeds_one(:target, MessageOne)
    end
  end

  defmodule MessageFour do
    @moduledoc false

    use Trogon.Ecto.ValueObject

    @enforce_keys [:targets]
    embedded_schema do
      embeds_many(:targets, MessageThree)
    end
  end

  defmodule BoxWithField do
    @moduledoc false

    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :content, MessageOne
    end
  end

  defmodule EmailContent do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    @enforce_keys [:subject, :body]
    embedded_schema do
      field :type, :string, default: "email"
      field :subject, :string
      field :body, :string
    end
  end

  defmodule SmsContent do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    @enforce_keys [:message, :phone]
    embedded_schema do
      field :type, :string, default: "sms"
      field :message, :string
      field :phone, :string
    end
  end

  defmodule NotificationWithPolymorphicEmbed do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    @enforce_keys [:title, :content]
    embedded_schema do
      field :title, :string

      polymorphic_embeds_one(:content,
        types: [
          email: Trogon.Ecto.TestSupport.EmailContent,
          sms: Trogon.Ecto.TestSupport.SmsContent
        ],
        on_type_not_found: :raise,
        on_replace: :update
      )
    end
  end

  defmodule MessageWithMultiplePolymorphicEmbeds do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    @enforce_keys [:title, :contents]
    embedded_schema do
      field :title, :string

      polymorphic_embeds_many(:contents,
        types: [
          email: Trogon.Ecto.TestSupport.EmailContent,
          sms: Trogon.Ecto.TestSupport.SmsContent
        ],
        on_type_not_found: :raise,
        on_replace: :delete
      )
    end
  end

  defmodule OptionalEmbeds do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :title, :string
      embeds_one(:target, MessageOne)
      embeds_many(:targets, MessageOne)
    end
  end

  defmodule OptionalPolymorphicEmbeds do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :title, :string

      polymorphic_embeds_one(:content,
        types: [
          email: Trogon.Ecto.TestSupport.EmailContent,
          sms: Trogon.Ecto.TestSupport.SmsContent
        ],
        on_type_not_found: :raise,
        on_replace: :update
      )

      polymorphic_embeds_many(:contents,
        types: [
          email: Trogon.Ecto.TestSupport.EmailContent,
          sms: Trogon.Ecto.TestSupport.SmsContent
        ],
        on_type_not_found: :raise,
        on_replace: :delete
      )
    end
  end

  defmodule UninterpolatedMessage do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :code, :string
    end

    def validate(changeset, _attrs) do
      Changeset.add_error(changeset, :code, "bad %{zzz_never_an_existing_atom_qqq}")
    end
  end

  defmodule BoxWithUninterpolatedMessage do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :content, UninterpolatedMessage
    end
  end

  defmodule InspectedMetadataMessage do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :code, :string
    end

    def validate(changeset, _attrs) do
      Changeset.add_error(changeset, :code, "got %{value}", value: [1, 2])
    end
  end

  defmodule MultiPlaceholderMessage do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :code, :string
    end

    def validate(changeset, _attrs) do
      Changeset.add_error(changeset, :code, "%{count} of %{kind}", count: 2, kind: :list)
    end
  end

  defmodule WithPrimaryKey do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    @primary_key {:id, :string, []}
    embedded_schema do
      field :title, :string
    end
  end

  defmodule WithAutogeneratedPrimaryKey do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    @primary_key {:id, :binary_id, autogenerate: true}
    embedded_schema do
      field :title, :string
    end
  end

  defmodule WithDuration do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :length, Trogon.Ecto.DurationType
    end
  end

  defmodule WithMapDuration do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :length, Trogon.Ecto.DurationType, format: :map
    end
  end

  defmodule BankAccountType do
    @moduledoc false
    use Trogon.Ecto.Enum, values: [:business, :personal]
  end

  defmodule BankAccountOpened do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    @enforce_keys [:uuid, :type]
    embedded_schema do
      field :uuid, :string
      field :type, Trogon.Ecto.TestSupport.BankAccountType
    end
  end

  defmodule BooleanNamedEnum do
    @moduledoc false
    use Trogon.Ecto.Enum, values: [true, false]
  end

  defmodule WithBoundedString do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :title, Trogon.Ecto.BoundedString, max_length: 5
    end
  end

  defmodule WithTruncatedBoundedString do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :title, Trogon.Ecto.BoundedString, max_length: 5, truncate: true
    end
  end

  defmodule WithStringMap do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :labels, Trogon.Ecto.StringMap
    end
  end

  defmodule WithConfiguredStringMap do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :labels, Trogon.Ecto.StringMap,
        key_format: :qualified_name,
        value_format: :label_value

      field :annotations, Trogon.Ecto.StringMap,
        key_format: :qualified_name,
        max_value_length: 64
    end
  end

  defmodule WithKubernetesMetadata do
    @moduledoc false
    use Trogon.Ecto.ValueObject

    embedded_schema do
      field :labels, Trogon.Ecto.LabelMap
      field :annotations, Trogon.Ecto.AnnotationMap, max_value_length: 64
    end
  end

  defmodule Basket do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      embeds_many :items, Item, on_replace: :delete, primary_key: {:id, :string, []} do
        field :sku, :string
      end
    end

    def changeset(basket, attrs) do
      basket
      |> Ecto.Changeset.cast(attrs, [])
      |> Ecto.Changeset.cast_embed(:items, with: &item_changeset/2)
    end

    defp item_changeset(item, attrs) do
      item
      |> Ecto.Changeset.cast(attrs, [:id, :sku])
      |> Ecto.Changeset.validate_required([:sku])
    end
  end

  def errors_on(changeset) do
    PolymorphicEmbed.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
