defmodule TestSupport do
  @moduledoc false

  defmodule MessageOne do
    @moduledoc false

    use Ecto.Schema
    use OnePiece.Commanded.ValueObject

    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageTwo do
    @moduledoc false

    use Ecto.Schema
    use OnePiece.Commanded.ValueObject

    @enforce_keys [:title]
    embedded_schema do
      field :title, :string
    end
  end

  defmodule MessageThree do
    @moduledoc false

    use Ecto.Schema
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

    use Ecto.Schema, aggregate_identifier: :uuid

    embedded_schema do
    end
  end

  defmodule MyEventOne do
    @moduledoc false

    use Ecto.Schema

    @primary_key {:uuid, :string, autogenerate: false}

    embedded_schema do
      field :name, :string
    end
  end

  defmodule MyEventTwo do
    @moduledoc false

    use Ecto.Schema, aggregate_identifier: :uuid

    @primary_key {:uuid, :string, autogenerate: false}

    embedded_schema do
      field :name, :string
    end
  end
end
