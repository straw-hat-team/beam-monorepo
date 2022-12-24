defmodule TestSupport do
  @moduledoc false

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

  defmodule MyEntityOne do
    @moduledoc false

    use OnePiece.Commanded.Entity, identifier: :uuid

    @enforce_keys [:name]
    embedded_schema do
      field :name, :string
    end
  end

  defmodule MyCommandOne do
    @moduledoc false

    use OnePiece.Commanded.Command, aggregate_identifier: :uuid

    embedded_schema do
    end
  end

  defmodule MyEventOne do
    @moduledoc false

    use OnePiece.Commanded.Event, aggregate_identifier: :uuid

    embedded_schema do
      field :name, :string
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

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
