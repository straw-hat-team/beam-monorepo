defmodule Trogon.Ecto.BoundedString do
  alias Trogon.Ecto.FieldOptions

  @own_keys [:max_length, :truncate]

  @opts_schema NimbleOptions.new!(
                 [
                   max_length: [
                     type: :pos_integer,
                     required: true,
                     doc: """
                     Maximum length, counted in characters rather than bytes, so
                     `max_length: 80` can outgrow a `varchar(80)` column.
                     """
                   ],
                   truncate: [
                     type: :boolean,
                     default: false,
                     doc: "Cut oversized values to fit instead of rejecting them."
                   ]
                 ] ++ FieldOptions.nimble_schema()
               )

  @moduledoc """
  A string field with a maximum length, enforced by the field rather than by
  every changeset that touches it.

      defmodule Product do
        use Ecto.Schema

        schema "products" do
          field :name, Trogon.Ecto.BoundedString, max_length: 80
          field :import_note, Trogon.Ecto.BoundedString, max_length: 256, truncate: true
        end
      end

  ## Options

  #{NimbleOptions.docs(@opts_schema)}

  An oversized value fails the changeset with
  `"should be at most %{count} character(s)"` and the metadata `count`,
  `validation: :length` and `kind: :max`.

  Under `truncate: true` the value is cut during `cast`, so the changeset holds
  the shortened string. Graphemes are never split.

  Reads are unbounded, so adding or tightening a bound never breaks existing
  rows. Writing a too-long value back is what fails.
  """

  use Ecto.ParameterizedType

  @typedoc "A field's bound and truncation policy, built by Ecto from `field/3`."
  @type params :: %{max_length: pos_integer(), truncate: boolean()}

  @impl Ecto.ParameterizedType
  @spec init(keyword()) :: params()
  def init(opts) do
    opts
    |> NimbleOptions.validate!(@opts_schema)
    |> Keyword.take(@own_keys)
    |> Map.new()
  end

  @impl Ecto.ParameterizedType
  @spec type(params()) :: :string
  def type(_params), do: :string

  @impl Ecto.ParameterizedType
  @spec cast(term(), params()) :: {:ok, String.t() | nil} | {:error, keyword()} | :error
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, %{max_length: max_length, truncate: truncate}) when is_binary(value) do
    case apply_bound(value, max_length, truncate) do
      {:ok, value} -> {:ok, value}
      :too_long -> {:error, too_long_error(max_length)}
    end
  end

  def cast(_value, _params), do: :error

  defp apply_bound(value, max_length, truncate) do
    cond do
      String.length(value) <= max_length -> {:ok, value}
      truncate -> {:ok, String.slice(value, 0, max_length)}
      true -> :too_long
    end
  end

  defp too_long_error(max_length) do
    [
      message: "should be at most %{count} character(s)",
      count: max_length,
      validation: :length,
      kind: :max,
      type: :string
    ]
  end

  @impl Ecto.ParameterizedType
  @spec load(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, String.t() | nil} | :error
  def load(nil, _loader, _params), do: {:ok, nil}
  def load(value, _loader, _params) when is_binary(value), do: {:ok, value}
  def load(_value, _loader, _params), do: :error

  @impl Ecto.ParameterizedType
  @spec dump(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, String.t() | nil} | :error
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, _dumper, %{max_length: max_length, truncate: truncate}) when is_binary(value) do
    case apply_bound(value, max_length, truncate) do
      {:ok, value} -> {:ok, value}
      :too_long -> :error
    end
  end

  def dump(_value, _dumper, _params), do: :error

  @impl Ecto.ParameterizedType
  @spec embed_as(atom(), params()) :: :dump
  def embed_as(_format, _params), do: :dump
end
