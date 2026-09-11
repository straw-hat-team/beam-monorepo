defmodule Trogon.Ecto.BoundedString do
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

  - `:max_length` - required, a positive integer. Counted in characters, not
    bytes, so `max_length: 80` can outgrow a `varchar(80)` column.
  - `:truncate` - cut oversized values to fit instead of rejecting them.
    Defaults to `false`.

  An oversized value fails the changeset the way
  `Ecto.Changeset.validate_length/3` does on a `:max` violation, with
  `"should be at most %{count} character(s)"`, `count`, `validation: :length`
  and `kind: :max`. Match on those rather than on `:type`.

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
    %{max_length: max_length!(opts), truncate: truncate!(opts)}
  end

  defp max_length!(opts) do
    case Keyword.fetch(opts, :max_length) do
      {:ok, max_length} ->
        validate_max_length!(max_length)

      :error ->
        raise ArgumentError,
              "missing :max_length for Trogon.Ecto.BoundedString, expected a positive integer"
    end
  end

  defp validate_max_length!(max_length) when is_integer(max_length) and max_length > 0, do: max_length

  defp validate_max_length!(other) do
    raise ArgumentError,
          "invalid :max_length #{inspect(other)} for Trogon.Ecto.BoundedString, " <>
            "expected a positive integer"
  end

  defp truncate!(opts) do
    opts
    |> Keyword.get(:truncate, false)
    |> validate_truncate!()
  end

  defp validate_truncate!(truncate) when is_boolean(truncate), do: truncate

  defp validate_truncate!(other) do
    raise ArgumentError,
          "invalid :truncate #{inspect(other)} for Trogon.Ecto.BoundedString, " <>
            "expected a boolean"
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
