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
      field :cooldown, Trogon.Ecto.DurationType, format: :native, equality: :storage

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

  ## The `:equality` option

  Decides what `equal?/3` treats as a change, and therefore when Ecto writes.

  - `:storage` - compare only what the column can tell apart. For `:native` that
    means folding years into `month`, weeks into `day`, hours and minutes into
    `second`, and ignoring the microsecond precision, none of which an `interval`
    keeps.
  - `:strict` - compare the `Duration` structs as they are.

  `format: :native` must state one, because the two genuinely differ there and the
  wrong one is expensive: under `:strict`, a `Duration.new!(second: 10)` reads back
  from the column as `%Duration{second: 10, microsecond: {0, 6}}` and never compares
  equal to itself, so Ecto issues an update on every save.

  For `:iso8601` and `:map` the option defaults to `:strict` and the two settings
  coincide, because both formats preserve the exact unit and the exact precision:
  `"PT10S"` and `"PT10.000000S"` are different strings, and `[0, 6]` is a different
  list from an omitted key.
  """

  use Ecto.ParameterizedType

  @postgres_default_precision 6

  @type format :: :iso8601 | :map | :native
  @type equality :: :storage | :strict
  @type params :: %{format: format(), equality: equality()}

  @doc """
  Initializes the parameterized type from the `:format` and `:equality` options.

  Ecto injects extra keys (`:field`, `:schema`) into `opts`; they are ignored.
  Raises `ArgumentError` when either option is not one of the supported values, or
  when `:equality` is missing for `format: :native`, which has no safe default.

  ## Examples

      iex> Trogon.Ecto.DurationType.init([])
      %{equality: :strict, format: :iso8601}

      iex> Trogon.Ecto.DurationType.init(format: :map)
      %{equality: :strict, format: :map}

      iex> Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
      %{equality: :storage, format: :native}

      iex> Trogon.Ecto.DurationType.init(format: :bogus)
      ** (ArgumentError) invalid :format :bogus for Trogon.Ecto.DurationType, expected one of :iso8601, :map, :native

      iex> Trogon.Ecto.DurationType.init(format: :native)
      ** (ArgumentError) missing :equality for Trogon.Ecto.DurationType with format: :native, expected one of :storage, :strict

      iex> Trogon.Ecto.DurationType.init(format: :native, equality: :bogus)
      ** (ArgumentError) invalid :equality :bogus for Trogon.Ecto.DurationType, expected one of :storage, :strict
  """
  @impl Ecto.ParameterizedType
  @spec init(keyword()) :: params()
  def init(opts) do
    format =
      opts
      |> Keyword.get(:format, :iso8601)
      |> validate_format!()

    %{format: format, equality: equality!(opts, format)}
  end

  defp validate_format!(format) when format in [:iso8601, :map, :native], do: format

  defp validate_format!(other) do
    raise ArgumentError,
          "invalid :format #{inspect(other)} for Trogon.Ecto.DurationType, " <>
            "expected one of :iso8601, :map, :native"
  end

  defp equality!(opts, :native) do
    case Keyword.fetch(opts, :equality) do
      {:ok, equality} ->
        validate_equality!(equality)

      :error ->
        raise ArgumentError,
              "missing :equality for Trogon.Ecto.DurationType with format: :native, " <>
                "expected one of :storage, :strict"
    end
  end

  defp equality!(opts, _format) do
    opts
    |> Keyword.get(:equality, :strict)
    |> validate_equality!()
  end

  defp validate_equality!(equality) when equality in [:storage, :strict], do: equality

  defp validate_equality!(other) do
    raise ArgumentError,
          "invalid :equality #{inspect(other)} for Trogon.Ecto.DurationType, " <>
            "expected one of :storage, :strict"
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

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
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

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
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

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
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
      {:ok,
       %Duration{
         month: value.months,
         day: value.days,
         second: value.secs,
         microsecond: {value.microsecs, @postgres_default_precision}
       }}
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

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
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
  Checks whether two durations are equal, as decided by the `:equality` option.

  Under `:strict`, and for every format other than `:native`, the structs are
  compared as they are, because `:iso8601` and `:map` round trip the exact unit and
  precision a duration was expressed in, so a change of either is a real change
  worth persisting.

  Under `:storage` with `format: :native`, both sides are first reduced to what the
  column can actually tell apart: years fold into `month`, weeks into `day`, hours
  and minutes into `second`, and the microsecond precision is dropped. None of those
  survive an `interval`, which stores months, days and a microsecond count and takes
  its precision from the column type rather than the value. Without this, a value
  written as `Duration.new!(year: 1)` would never compare equal to the
  `%Duration{month: 12}` it reads back as, and Ecto would issue an update on every
  save.

  ## Examples

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(second: 10), Duration.new!(second: 10), params)
      true

      iex> params = Trogon.Ecto.DurationType.init([])
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(second: 10), Duration.new!(minute: 1), params)
      false

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(year: 1), Duration.new!(month: 12), params)
      true

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(month: 1), Duration.new!(day: 30), params)
      false

  Precision is ignored under `:storage`, which is what keeps a round-tripped value
  from looking dirty:

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(second: 10), Duration.new!(second: 10, microsecond: {0, 6}), params)
      true

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :strict)
      iex> Trogon.Ecto.DurationType.equal?(Duration.new!(second: 10), Duration.new!(second: 10, microsecond: {0, 6}), params)
      false
  """
  @impl Ecto.ParameterizedType
  @spec equal?(term(), term(), params()) :: boolean()
  def equal?(%Duration{} = value1, %Duration{} = value2, %{format: :native, equality: :storage}) do
    postgres_components(value1) == postgres_components(value2)
  end

  def equal?(value1, value2, _params), do: value1 == value2

  defp postgres_components(%Duration{} = duration) do
    {microsecond, _precision} = duration.microsecond

    [
      month: 12 * duration.year + duration.month,
      day: 7 * duration.week + duration.day,
      second: 3600 * duration.hour + 60 * duration.minute + duration.second,
      microsecond: microsecond
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

      iex> params = Trogon.Ecto.DurationType.init(format: :native, equality: :storage)
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

  defp duration_from_map(map), do: duration_from_pairs(Map.to_list(map), %Duration{})

  defp duration_from_pairs([], duration), do: {:ok, duration}

  defp duration_from_pairs([{key, value} | rest], duration) do
    case put_duration_component(duration, key, value) do
      {:ok, duration} -> duration_from_pairs(rest, duration)
      :error -> :error
    end
  end

  defp put_duration_component(duration, :year, value) when is_integer(value),
    do: {:ok, %{duration | year: value}}

  defp put_duration_component(duration, "year", value) when is_integer(value),
    do: {:ok, %{duration | year: value}}

  defp put_duration_component(duration, :month, value) when is_integer(value),
    do: {:ok, %{duration | month: value}}

  defp put_duration_component(duration, "month", value) when is_integer(value),
    do: {:ok, %{duration | month: value}}

  defp put_duration_component(duration, :week, value) when is_integer(value),
    do: {:ok, %{duration | week: value}}

  defp put_duration_component(duration, "week", value) when is_integer(value),
    do: {:ok, %{duration | week: value}}

  defp put_duration_component(duration, :day, value) when is_integer(value),
    do: {:ok, %{duration | day: value}}

  defp put_duration_component(duration, "day", value) when is_integer(value),
    do: {:ok, %{duration | day: value}}

  defp put_duration_component(duration, :hour, value) when is_integer(value),
    do: {:ok, %{duration | hour: value}}

  defp put_duration_component(duration, "hour", value) when is_integer(value),
    do: {:ok, %{duration | hour: value}}

  defp put_duration_component(duration, :minute, value) when is_integer(value),
    do: {:ok, %{duration | minute: value}}

  defp put_duration_component(duration, "minute", value) when is_integer(value),
    do: {:ok, %{duration | minute: value}}

  defp put_duration_component(duration, :second, value) when is_integer(value),
    do: {:ok, %{duration | second: value}}

  defp put_duration_component(duration, "second", value) when is_integer(value),
    do: {:ok, %{duration | second: value}}

  defp put_duration_component(duration, :microsecond, {value, precision})
       when is_integer(value) and precision in 0..6,
       do: {:ok, %{duration | microsecond: {value, precision}}}

  defp put_duration_component(duration, :microsecond, [value, precision])
       when is_integer(value) and precision in 0..6,
       do: {:ok, %{duration | microsecond: {value, precision}}}

  defp put_duration_component(duration, "microsecond", {value, precision})
       when is_integer(value) and precision in 0..6,
       do: {:ok, %{duration | microsecond: {value, precision}}}

  defp put_duration_component(duration, "microsecond", [value, precision])
       when is_integer(value) and precision in 0..6,
       do: {:ok, %{duration | microsecond: {value, precision}}}

  defp put_duration_component(_duration, _key, _value), do: :error

  @compile {:inline, put_component: 3, put_microsecond: 2}

  defp to_component_map(%Duration{} = duration) do
    []
    |> put_component("year", duration.year)
    |> put_component("month", duration.month)
    |> put_component("week", duration.week)
    |> put_component("day", duration.day)
    |> put_component("hour", duration.hour)
    |> put_component("minute", duration.minute)
    |> put_component("second", duration.second)
    |> put_microsecond(duration.microsecond)
    |> :maps.from_list()
  end

  defp put_component(components, _key, 0), do: components
  defp put_component(components, key, value), do: [{key, value} | components]

  defp put_microsecond(components, {0, 0}), do: components

  defp put_microsecond(components, {value, precision}),
    do: [{"microsecond", [value, precision]} | components]
end
