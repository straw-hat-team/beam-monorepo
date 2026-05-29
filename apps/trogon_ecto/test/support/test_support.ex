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

  def errors_on(changeset) do
    PolymorphicEmbed.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
