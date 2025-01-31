defmodule TestSupport do
  @moduledoc false

  defmodule TransferableMoney do
    @moduledoc false
    use OnePiece.Commanded.ValueObject

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
    use OnePiece.Commanded.ValueObject

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
    use OnePiece.Commanded.ValueObject

    embedded_schema do
      field :branch, :string
      field :account_number, :string
    end
  end

  defmodule MessageOne do
    @moduledoc false

    use OnePiece.Commanded.ValueObject

    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageTwo do
    @moduledoc false

    use OnePiece.Commanded.ValueObject

    @enforce_keys [:title]
    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageThree do
    @moduledoc false

    use OnePiece.Commanded.ValueObject

    @enforce_keys [:target]
    embedded_schema do
      embeds_one(:target, MessageOne)
    end
  end

  defmodule MessageFour do
    @moduledoc false

    use OnePiece.Commanded.ValueObject

    @enforce_keys [:targets]
    embedded_schema do
      embeds_many(:targets, MessageThree)
    end
  end

  defmodule MyEntityOne do
    @moduledoc false

    use OnePiece.Commanded.Entity, identifier: :uuid

    @enforce_keys [:name]
    embedded_schema do
      field :name, :string
    end
  end

  defmodule BankAccountEntity do
    @moduledoc false

    use OnePiece.Commanded.Entity, identifier: {:uuid, AccountNumber}

    @enforce_keys [:type]
    embedded_schema do
      field :type, Ecto.Enum, values: [:DEPOSITORY]
    end
  end

  defmodule MyCommandOne do
    @moduledoc false

    use OnePiece.Commanded.Command, aggregate_identifier: :uuid

    embedded_schema do
    end
  end

  defmodule OpenDepositAccountCommand do
    @moduledoc false

    use OnePiece.Commanded.Command, aggregate_identifier: {:uuid, AccountNumber}

    @enforce_keys [:type]
    embedded_schema do
      field :type, Ecto.Enum, values: [:DEPOSITORY]
    end
  end

  defmodule MyEventOne do
    @moduledoc false

    use OnePiece.Commanded.Event, aggregate_identifier: :uuid

    embedded_schema do
      field :name, :string
    end
  end

  defmodule DepositAccountOpened do
    @moduledoc false

    use OnePiece.Commanded.Event, aggregate_identifier: {:uuid, AccountNumber}

    embedded_schema do
      field :type, Ecto.Enum, values: [:DEPOSITORY]
    end
  end

  defmodule MyEventTwo do
    @moduledoc false

    use OnePiece.Commanded.Event, aggregate_identifier: :uuid

    embedded_schema do
      field :name, :string
    end
  end

  defmodule MyAggregateOne do
    @moduledoc false

    use OnePiece.Commanded.Aggregate, identifier: :uuid

    embedded_schema do
      field :name, :string
    end

    @impl OnePiece.Commanded.Aggregate
    def apply(aggregate, %MyEventOne{} = event) do
      aggregate
      |> Map.put(:uuid, event.uuid)
      |> Map.put(:name, event.name)
    end
  end

  defmodule DefaultApp do
    @moduledoc false
    use Commanded.Application,
      otp_app: :one_piece_commanded,
      event_store: [
        adapter: Commanded.EventStore.Adapters.InMemory,
        serializer: Commanded.Serialization.JsonSerializer
      ],
      pubsub: :local,
      registry: :local
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
