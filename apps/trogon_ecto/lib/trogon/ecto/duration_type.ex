defmodule Trogon.Ecto.DurationType do
  @moduledoc """
  An `Ecto.ParameterizedType` that wraps Elixir's `Duration`, persisted as an ISO
  8601 string, a map of its components, or a native PostgreSQL `interval`.

  ## When NOT to use this type

  If your column only ever holds a plain `interval`, you never feed it an ISO
  8601 string or a component map, and you would rather not take on the
  dependency, use Ecto's built-in `:duration` type directly instead. Otherwise,
  reach for this type and pick the `:format` below that matches how you plan to
  query and store the value.

  ## The `:format` option

  - `:iso8601` (the default) - persists as an ISO 8601 string, e.g. `"PT10S"`.
    `type/1` is `:string`. Exact round trip, embeddable, portable, and still
    SQL-comparable on demand since PostgreSQL parses ISO 8601 durations natively,
    e.g. `WHERE (col::interval) > interval 'PT1M'`.
  - `:map` - persists as a map of components, omitting zero-valued ones. `type/1`
    is `:map`. Exact round trip, embeddable, and per-component queryable in
    `jsonb`.
  - `:native` - persists as a native PostgreSQL `interval`, via `type/1` being
    `:duration`. Gives you SQL-level comparison, sorting, and arithmetic directly
    on the column, but it is **not embeddable** and it is **lossy across a
    database round trip** - see below.

  The map representation uses string keys: `"year"`, `"month"`, `"week"`, `"day"`,
  `"hour"`, `"minute"`, `"second"`, and `"microsecond"` as a two-element list
  `[value, precision]` (a tuple is not JSON encodable). Zero-valued components are
  omitted, including `"microsecond"` when it is `{0, 0}`.

      field :cooldown, Trogon.Ecto.DurationType
      field :cooldown, Trogon.Ecto.DurationType, format: :map
      field :cooldown, Trogon.Ecto.DurationType, format: :native

  `load/3` accepts either stored shape (an ISO 8601 binary or a component map)
  regardless of the configured format, so a column holding a mix of both during a
  transition still reads cleanly.

  That leniency is about reading, not about switching formats for free. Each format
  selects a different underlying Ecto type (`:string`, `:map`, `:duration`), so
  changing a field's `:format` still requires migrating the column and its existing
  values. A `text` column will reject the map that `format: :map` dumps, however
  liberally `load/3` reads. Cross-shape loading only helps where the database
  representation is already compatible with both.

  ## `:native` is lossy across a database round trip

  This is a property of PostgreSQL's `interval` type, not of this library.
  Postgrex flattens the struct on the way in (`12 * year + month`,
  `7 * week + day`, everything below a day collapsed into microseconds) and only
  ever reconstructs `month`, `day`, `second`, and `microsecond` on the way out, so
  a stored `Duration.new!(year: 1)` reads back as `%Duration{month: 12}` -
  arithmetically equal, not struct-equal. `:iso8601` and `:map` preserve the exact
  unit a duration was expressed in; prefer them unless you specifically need
  SQL-level arithmetic over the column.

  Postgrex also decodes `interval` columns to `%Postgrex.Interval{}` by default,
  not `Duration`; this type's `load/3` accepts both. If you would rather have
  Postgrex hand you a `Duration` directly (outside of this type), set
  `interval_decode_type: Duration` on the connection.

  Because dumping a `:native` duration yields a bare `%Duration{}` struct with no
  JSON encoder, `:native` cannot be used inside an embed or value object; `embed_as/2`
  raises for it.
  """

  use Ecto.ParameterizedType

  @component_atoms ~w(year month week day hour minute second microsecond)a
  @component_strings Enum.map(@component_atoms, &Atom.to_string/1)
  @postgres_default_precision 6

  @type format :: :iso8601 | :map | :native
  @type params :: %{format: format()}

  @doc """
  Initializes the parameterized type from the `:format` option.

  Ecto injects extra keys (`:field`, `:schema`) into `opts`; they are ignored.
  Raises `ArgumentError` when `:format` is not one of the supported values.

  ## Examples

      iex> Trogon.Ecto.DurationType.init([])
      %{format: :iso8601}

      iex> Trogon.Ecto.DurationType.init(format: :map)
      %{format: :map}

      iex> Trogon.Ecto.DurationType.init(format: :native)
      %{format: :native}

      iex> Trogon.Ecto.DurationType.init(format: :bogus)
      ** (ArgumentError) invalid :format :bogus for Trogon.Ecto.DurationType, expected one of :iso8601, :map, :native
  """
  @impl Ecto.ParameterizedType
  @spec init(keyword()) :: params()
  def init(opts) do
    format =
      opts
      |> Keyword.get(:format, :iso8601)
      |> validate_format!()

    %{format: format}
  end

  defp validate_format!(format) when format in [:iso8601, :map, :native], do: format

  defp validate_format!(other) do
    raise ArgumentError,
          "invalid :format #{inspect(other)} for Trogon.Ecto.DurationType, " <>
            "expected one of :iso8601, :map, :native"
  end

  @doc """
  Returns the underlying Ecto type used to persist the value.

  `:string` for `:iso8601`, `:map` for `:map`, `:duration` (a native interval)
  for `:native`.

  ## Examples

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.type(params)
      :string

      iex> params = Trogon.Ecto.DurationType.init(format: :map)
      iex> Trogon.Ecto.DurationType.type(params)
      :map

      iex> params = Trogon.Ecto.DurationType.init(format: :native)
      iex> Trogon.Ecto.DurationType.type(params)
      :duration
  """
  @impl Ecto.ParameterizedType
  @spec type(params()) :: :string | :map | :duration
  def type(%{format: :iso8601}), do: :string
  def type(%{format: :map}), do: :map
  def type(%{format: :native}), do: :duration

  @doc """
  Casts a value into a `t:Duration.t/0`, regardless of the configured format.

  Accepts a `Duration` struct as-is, an ISO 8601 binary, a component map with
  either string or atom keys, and `nil`. Anything else, or a map that does not
  describe a valid duration, returns `:error`. This holds for `:native` too: unlike
  Ecto's built-in `:duration`, which only casts a `Duration` struct, this type
  also accepts an ISO 8601 string.

  ## Examples

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.cast(Duration.new!(second: 10), params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.cast("PT10S", params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.cast(%{"second" => 10}, params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.cast(%{second: 10}, params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init(format: :native)
      iex> Trogon.Ecto.DurationType.cast("PT10S", params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.cast(nil, params)
      {:ok, nil}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.cast("random value", params)
      :error

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.cast(123, params)
      :error
  """
  @impl Ecto.ParameterizedType
  @spec cast(term(), params()) :: {:ok, Duration.t() | nil} | :error
  def cast(%Duration{} = value, _params), do: {:ok, value}
  def cast(nil, _params), do: {:ok, nil}

  def cast(value, _params) when is_binary(value) do
    case Duration.from_iso8601(value) do
      {:ok, duration} -> {:ok, duration}
      {:error, _reason} -> :error
    end
  end

  def cast(value, _params) when is_map(value), do: duration_from_map(value)
  def cast(_value, _params), do: :error

  @doc """
  Loads a value from the database into a `t:Duration.t/0`.

  Accepts either stored shape (an ISO 8601 binary or a component map), regardless
  of the configured format, plus a `Duration` struct and `nil`. This is deliberate:
  it lets a field's `:format` be changed later without a data migration.

  For `:native`, also accepts a `Postgrex.Interval` - what Postgrex decodes an
  `interval` column into by default (it only returns a `Duration` when the
  connection is configured with `interval_decode_type: Duration`), converted to a
  `Duration` with `month`, `day`, `second`, and `microsecond` set from its
  `months`, `days`, `secs`, and `microsecs` fields.

  ## Examples

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.load("PT10S", & &1, params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init(format: :iso8601)
      iex> Trogon.Ecto.DurationType.load(%{"second" => 10}, & &1, params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init(format: :map)
      iex> Trogon.Ecto.DurationType.load("PT10S", & &1, params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init(format: :native)
      iex> Trogon.Ecto.DurationType.load(%Postgrex.Interval{months: 0, days: 0, secs: 10, microsecs: 0}, & &1, params)
      {:ok, Duration.new!(second: 10, microsecond: {0, 6})}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.load(nil, & &1, params)
      {:ok, nil}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.load("random value", & &1, params)
      :error
  """
  @impl Ecto.ParameterizedType
  @spec load(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, Duration.t() | nil} | :error
  def load(%Duration{} = value, _loader, _params), do: {:ok, value}
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(value, _loader, _params) when is_binary(value) do
    case Duration.from_iso8601(value) do
      {:ok, duration} -> {:ok, duration}
      {:error, _reason} -> :error
    end
  end

  if Code.ensure_loaded?(Postgrex.Interval) do
    def load(%Postgrex.Interval{} = value, _loader, _params) do
      %Postgrex.Interval{months: months, days: days, secs: secs, microsecs: microsecs} = value

      {:ok,
       Duration.new!(
         month: months,
         day: days,
         second: secs,
         microsecond: {microsecs, @postgres_default_precision}
       )}
    end
  end

  def load(value, _loader, _params) when is_map(value), do: duration_from_map(value)
  def load(_value, _loader, _params), do: :error

  @doc """
  Dumps a `t:Duration.t/0` using the configured format, strictly.

  For `:native`, the `Duration` struct is passed straight through; Postgrex
  encodes it for the `interval` column.

  ## Examples

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.dump(Duration.new!(second: 10), & &1, params)
      {:ok, "PT10S"}

      iex> params = Trogon.Ecto.DurationType.init(format: :map)
      iex> Trogon.Ecto.DurationType.dump(Duration.new!(second: 10), & &1, params)
      {:ok, %{"second" => 10}}

      iex> params = Trogon.Ecto.DurationType.init(format: :native)
      iex> Trogon.Ecto.DurationType.dump(Duration.new!(second: 10), & &1, params)
      {:ok, Duration.new!(second: 10)}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.dump(nil, & &1, params)
      {:ok, nil}

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.dump("random value", & &1, params)
      :error
  """
  @impl Ecto.ParameterizedType
  @spec dump(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, String.t() | map() | Duration.t() | nil} | :error
  def dump(nil, _dumper, _params), do: {:ok, nil}
  def dump(%Duration{} = value, _dumper, %{format: :iso8601}), do: {:ok, Duration.to_iso8601(value)}
  def dump(%Duration{} = value, _dumper, %{format: :map}), do: {:ok, to_component_map(value)}
  def dump(%Duration{} = value, _dumper, %{format: :native}), do: {:ok, value}
  def dump(_value, _dumper, _params), do: :error

  @doc """
  Checks whether two durations are equal.

  For `:iso8601` and `:map`, equality is structural, because those formats round
  trip the exact unit a duration was expressed in and so a change of unit is a real
  change worth persisting.

  For `:native` both sides are first reduced to the `Duration.new!/1` arguments an
  `interval` collapses them into, folding years into `month`, weeks into `day` and
  hours and minutes into `second`, since those units do not survive the column.
  Without this, a value loaded back as `%Duration{month: 12}` would never compare
  equal to the `Duration.new!(year: 1)` it was written from, and Ecto would issue
  an update on every save.

  Microsecond precision is carried through the comparison rather than normalized
  away, so two durations holding the same microsecond count at different precisions
  are not equal.

  ## Examples

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(second: 10), Duration.new!(second: 10), params)
      true

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(second: 10), Duration.new!(minute: 1), params)
      false

      iex> params = Trogon.Ecto.DurationType.init(format: :native)
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(year: 1), Duration.new!(month: 12), params)
      true

      iex> params = Trogon.Ecto.DurationType.init(format: :native)
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(month: 1), Duration.new!(day: 30), params)
      false
  """
  @impl Ecto.ParameterizedType
  @spec equal?(term(), term(), params()) :: boolean()
  def equal?(%Duration{} = value1, %Duration{} = value2, %{format: :native}) do
    postgres_components(value1) == postgres_components(value2)
  end

  def equal?(value1, value2, _params), do: value1 == value2

  defp postgres_components(%Duration{} = duration) do
    [
      month: 12 * duration.year + duration.month,
      day: 7 * duration.week + duration.day,
      second: 3600 * duration.hour + 60 * duration.minute + duration.second,
      microsecond: duration.microsecond
    ]
  end

  @doc """
  Returns how the value is persisted when the type is used inside an embed.

  `:dump` for `:iso8601` and `:map`, so a `Duration` nested in a value object or
  embedded schema is persisted as its ISO 8601 string or component map rather than
  as a bare struct. `:native` raises `ArgumentError`: dumping it yields a
  `%Duration{}` struct, which has no JSON encoder, so it cannot be stored inside an
  embed or value object.

  ## Examples

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.embed_as(:json, params)
      :dump

      iex> params = Trogon.Ecto.DurationType.init(format: :map)
      iex> Trogon.Ecto.DurationType.embed_as(:json, params)
      :dump

      iex> params = Trogon.Ecto.DurationType.init(format: :native)
      iex> Trogon.Ecto.DurationType.embed_as(:json, params)
      ** (ArgumentError) a :native Trogon.Ecto.DurationType cannot be stored inside an embed or value object; use format: :iso8601 or format: :map instead
  """
  @impl Ecto.ParameterizedType
  @spec embed_as(atom(), params()) :: :dump
  def embed_as(_format, %{format: :native}) do
    raise ArgumentError,
          "a :native Trogon.Ecto.DurationType cannot be stored inside an embed or value " <>
            "object; use format: :iso8601 or format: :map instead"
  end

  def embed_as(_format, _params), do: :dump

  defp duration_from_map(map) do
    case normalize_components(Map.to_list(map), []) do
      {:ok, opts} -> build_duration(opts)
      :error -> :error
    end
  end

  defp build_duration(opts) do
    {:ok, Duration.new!(opts)}
  rescue
    ArgumentError -> :error
  end

  defp normalize_components([], acc), do: {:ok, acc}

  defp normalize_components([{key, value} | rest], acc) do
    with {:ok, component} <- normalize_key(key) do
      normalize_components(rest, [{component, normalize_value(component, value)} | acc])
    end
  end

  defp normalize_key(key) when key in @component_atoms, do: {:ok, key}

  defp normalize_key(key) when is_binary(key) do
    if key in @component_strings do
      {:ok, String.to_existing_atom(key)}
    else
      :error
    end
  end

  defp normalize_key(_key), do: :error

  defp normalize_value(:microsecond, [value, precision]), do: {value, precision}
  defp normalize_value(_component, value), do: value

  @compile {:inline, put_component: 3, put_microsecond: 2}

  defp to_component_map(%Duration{
         year: year,
         month: month,
         week: week,
         day: day,
         hour: hour,
         minute: minute,
         second: second,
         microsecond: microsecond
       }) do
    []
    |> put_component("year", year)
    |> put_component("month", month)
    |> put_component("week", week)
    |> put_component("day", day)
    |> put_component("hour", hour)
    |> put_component("minute", minute)
    |> put_component("second", second)
    |> put_microsecond(microsecond)
    |> :maps.from_list()
  end

  defp put_component(components, _key, 0), do: components
  defp put_component(components, key, value), do: [{key, value} | components]

  defp put_microsecond(components, {0, 0}), do: components

  defp put_microsecond(components, {value, precision}),
    do: [{"microsecond", [value, precision]} | components]
end
