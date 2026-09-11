defmodule Trogon.Ecto.BoundedString do
  @moduledoc """
  A string field with a maximum length, declared on the field instead of
  restated in every changeset.

      defmodule Product do
        use Ecto.Schema

        schema "products" do
          field :name, Trogon.Ecto.BoundedString, max_length: 80
          field :import_note, Trogon.Ecto.BoundedString, max_length: 256, truncate: true
        end
      end

  `:max_length` is required and must be a positive integer. `:truncate` is
  optional and defaults to `false`.

  ## When a value is too long

  The changeset fails the way `Ecto.Changeset.validate_length/3` fails on a
  `:max` violation: the message `"should be at most %{count} character(s)"`,
  alongside `count`, `validation: :length` and `kind: :max`. Whatever already
  renders your validation errors keeps working, and the wording stays consistent
  with the fields you bound by hand.

  The reason to declare the bound here rather than call `validate_length/3` is
  that it cannot be forgotten. It applies to every changeset that touches the
  field, and to code that writes the field without a changeset at all, which
  would otherwise reach the database unchecked.

  If you render errors by matching on metadata, match `validation: :length` and
  `kind: :max`. Avoid matching on `:type`, which holds this type rather than
  `:string` when the error comes from a changeset.

  ## Truncating instead of failing

  With `truncate: true` an oversized value is cut to fit instead of rejected.

  Reach for it when the text is something you are recording rather than
  validating, and losing the tail beats losing the write: a vendor's error
  message, an upstream description, a log line. Leave it off for anything a
  person typed and expects back verbatim, where silently changing their input is
  worse than telling them it was too long.

  The value is cut as it is cast, so the shortened string is what the changeset
  holds and what every later validation sees, not a surprise applied on the way
  to the database. Characters are never split in half.

  ## Rows that are already too long

  Reads are never bounded, so adding a bound, or tightening one, does not break
  existing rows. Updating other fields on such a row keeps working too.

  Writing the too-long value back is what fails, which is usually what you want,
  since that row no longer satisfies the field. Migrate it, widen the bound, or
  set `truncate: true` to accept the loss.

  ## Sizing the column

  The bound counts characters, while a `varchar(n)` column counts bytes, and
  multi-byte text takes more bytes than it has characters. Give the column room
  to spare, or make it `text` and let this type be the limit.
  """

  use Ecto.ParameterizedType

  @typedoc """
  The bound and policy for a field, built by Ecto from the options given to
  `field/3`.
  """
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
