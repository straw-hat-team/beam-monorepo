defmodule Trogon.Ecto.BoundedString do
  @moduledoc """
  An `Ecto.ParameterizedType` for a string bounded to a maximum length, declared
  at the field rather than restated in every changeset.

      field :title, Trogon.Ecto.BoundedString, max_length: 80
      field :error, Trogon.Ecto.BoundedString, max_length: 256, truncate: true

  The bound travels with the field, so it holds for every write path into it,
  including the ones that never call `Ecto.Changeset.validate_length/3`. It is
  enforced twice over: on `cast/2`, where it produces a validation error you can
  render, and again on `dump/3`, which catches the paths that skip casting
  altogether (`Ecto.Changeset.put_change/3`, `Ecto.Changeset.change/2`,
  `struct!/2`).

  ## The `:max_length` option

  Required, a positive integer. Counts graphemes, matching
  `Ecto.Changeset.validate_length/3` and never splitting a character. The
  serialized byte size of multi-byte text can exceed it, so this bounds order of
  magnitude, not exact bytes; size a `varchar` column accordingly, or prefer
  `text` and let the type be the bound.

  ## The `:truncate` option

  Decides what an oversized value means.

  - `false` (the default) - an oversized value is a cast error, carrying the same
    message and metadata (`count`, `validation: :length`, `kind: :max`) that
    `Ecto.Changeset.validate_length/3` would have produced, so existing error
    traversal and translation keep working unchanged.
  - `true` - the value is silently cut at the bound instead.

  Reserve `truncate: true` for diagnostic text sourced from unbounded external
  payloads (vendor HTTP bodies, gRPC status messages), where recording a lossy
  detail beats failing the command that records it. For anything a user typed and
  expects back verbatim, leave it off and let the cast fail.

  Truncation happens on cast, so the shortened value is what the changeset holds
  and what every later validation sees, not a surprise applied on the way to the
  database.

  ## The `:type` metadata differs inside a changeset

  `cast/2` returns `type: :string`, but `Ecto.Changeset` overwrites the `:type`
  metadata of a custom type error with the type the field was declared as. A
  violation surfaced through a changeset therefore carries
  `type: {:parameterized, {Trogon.Ecto.BoundedString, params}}`, not
  `type: :string`.

  That is the declared type rather than the stored one, and it is the more useful
  of the two, since it names which type rejected the value and carries its
  `:max_length`. Resolve it to the storage type with `Ecto.Type.type/1` when a
  primitive is what you need:

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Ecto.Type.type({:parameterized, {Trogon.Ecto.BoundedString, params}})
      :string

  Error translation should match on `validation: :length` and `kind: :max`, which
  survive both paths. Code that renders `:type` must also tolerate a non-string
  term there, since interpolating it with `to_string/1` raises for a tuple.

  ## Reads are lenient, writes are not

  `load/3` accepts any binary, whatever the bound, while `cast/2` and `dump/3`
  both enforce it. A column whose values predate the bound, or predate a
  tightening of it, still reads cleanly; only writes are held to it.

  That asymmetry is deliberate, and it is what makes tightening a bound
  survivable. Ecto dumps only the fields a changeset actually changed, so a
  legacy row whose oversized field is left alone updates normally:

      # works, even though `title` is over the bound in the database
      record |> Ecto.Changeset.change(%{other_field: "new"}) |> Repo.update()

  What does fail is writing an oversized value back, whether it came from
  `struct!/2` or from a row loaded before the bound existed. Copying a legacy row
  verbatim is the case to watch. Treat the resulting `Ecto.ChangeError` as the
  intended answer: the row no longer satisfies the field's contract, so either
  migrate it, widen the bound, or set `truncate: true` to accept the loss.
  """

  use Ecto.ParameterizedType

  @type params :: %{max_length: pos_integer(), truncate: boolean()}

  @doc """
  Initializes the parameterized type from the `:max_length` and `:truncate` options.

  Ecto injects extra keys (`:field`, `:schema`) into `opts`; they are ignored.
  Raises `ArgumentError` when `:max_length` is missing or is not a positive
  integer, or when `:truncate` is not a boolean.

  ## Examples

      iex> Trogon.Ecto.BoundedString.init(max_length: 80)
      %{max_length: 80, truncate: false}

      iex> Trogon.Ecto.BoundedString.init(max_length: 256, truncate: true)
      %{max_length: 256, truncate: true}

      iex> Trogon.Ecto.BoundedString.init([])
      ** (ArgumentError) missing :max_length for Trogon.Ecto.BoundedString, expected a positive integer

      iex> Trogon.Ecto.BoundedString.init(max_length: 0)
      ** (ArgumentError) invalid :max_length 0 for Trogon.Ecto.BoundedString, expected a positive integer

      iex> Trogon.Ecto.BoundedString.init(max_length: 80, truncate: :yes)
      ** (ArgumentError) invalid :truncate :yes for Trogon.Ecto.BoundedString, expected a boolean
  """
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

  @doc """
  Returns the underlying Ecto type used to persist the value, always `:string`.

  ## Examples

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 80)
      iex> Trogon.Ecto.BoundedString.type(params)
      :string
  """
  @impl Ecto.ParameterizedType
  @spec type(params()) :: :string
  def type(_params), do: :string

  @doc """
  Casts a binary, holding it to the configured bound.

  A value within the bound is returned as-is, and `nil` passes through. An
  oversized value is cut at the bound under `truncate: true`, and otherwise
  returns the `Ecto.Changeset.validate_length/3` error metadata for a `:max`
  violation. Anything that is not a binary returns `:error`.

  ## Examples

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.cast("hello", params)
      {:ok, "hello"}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.cast(nil, params)
      {:ok, nil}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.cast("hello world", params)
      {:error, [message: "should be at most %{count} character(s)", count: 5, validation: :length, kind: :max, type: :string]}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5, truncate: true)
      iex> Trogon.Ecto.BoundedString.cast("hello world", params)
      {:ok, "hello"}

  Graphemes are counted, and never split:

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 2, truncate: true)
      iex> Trogon.Ecto.BoundedString.cast("héllo", params)
      {:ok, "hé"}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.cast(:hello, params)
      :error
  """
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

  @doc """
  Loads a binary from the database, without holding it to the bound.

  ## Examples

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.load("hello", & &1, params)
      {:ok, "hello"}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.load("a value stored before the bound", & &1, params)
      {:ok, "a value stored before the bound"}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.load(nil, & &1, params)
      {:ok, nil}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.load(123, & &1, params)
      :error
  """
  @impl Ecto.ParameterizedType
  @spec load(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, String.t() | nil} | :error
  def load(nil, _loader, _params), do: {:ok, nil}
  def load(value, _loader, _params) when is_binary(value), do: {:ok, value}
  def load(_value, _loader, _params), do: :error

  @doc """
  Dumps a binary, holding it to the configured bound.

  Applies the same policy as `cast/2`, because `cast/2` is not the only way into
  a field. `Ecto.Changeset.put_change/3`, `Ecto.Changeset.change/2` and
  `struct!/2` all write a field without casting it, so dump is the last gate
  before the value reaches the database.

  A dump failure is a `:error` rather than the metadata `cast/2` returns, since
  `c:Ecto.ParameterizedType.dump/3` has nowhere to put it; Ecto raises
  `Ecto.ChangeError`. That is the right shape for this failure: user input
  arrives through `cast/2`, so an oversized value here is a bug in the calling
  code, not something to render back as a validation error.

  ## Examples

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.dump("hello", & &1, params)
      {:ok, "hello"}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.dump(nil, & &1, params)
      {:ok, nil}

  An oversized value is refused, so a field written without casting cannot
  escape the bound:

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.dump("hello world", & &1, params)
      :error

  Under `truncate: true` it is cut instead, matching `cast/2`:

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5, truncate: true)
      iex> Trogon.Ecto.BoundedString.dump("hello world", & &1, params)
      {:ok, "hello"}

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.dump(123, & &1, params)
      :error
  """
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

  @doc """
  Returns how the value is persisted when the type is used inside an embed,
  always `:dump`.

  ## Examples

      iex> params = Trogon.Ecto.BoundedString.init(max_length: 5)
      iex> Trogon.Ecto.BoundedString.embed_as(:json, params)
      :dump
  """
  @impl Ecto.ParameterizedType
  @spec embed_as(atom(), params()) :: :dump
  def embed_as(_format, _params), do: :dump
end
