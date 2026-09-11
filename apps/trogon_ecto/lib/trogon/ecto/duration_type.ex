defmodule Trogon.Ecto.DurationType do
  alias Trogon.Ecto.FieldOptions

  @opts_schema NimbleOptions.new!(
                 [
                   format: [
                     type: {:in, [:iso8601, :map, :native]},
                     default: :iso8601,
                     doc: """
                     How the duration is persisted: `:iso8601` as a string, `:map` as a map of
                     its components, `:native` as a PostgreSQL `interval`.
                     """
                   ],
                   equality: [
                     type: {:in, [:storage, :strict]},
                     doc: """
                     What `equal?/3` treats as a change, and therefore when Ecto writes.
                     `:strict` compares the `Duration` structs as they are, `:storage` compares
                     only what the column can tell apart. Defaults to `:strict`, except for
                     `format: :native`, where it is required.
                     """
                   ]
                 ] ++ FieldOptions.nimble_schema()
               )

  @moduledoc """
  A `Duration` field, persisted as an ISO 8601 string, a map of its components,
  or a native PostgreSQL `interval`.

      defmodule Offer do
        use Ecto.Schema

        schema "offers" do
          field :cooldown, Trogon.Ecto.DurationType
          field :window, Trogon.Ecto.DurationType, format: :map
          field :ttl, Trogon.Ecto.DurationType, format: :native, equality: :storage
        end
      end

  ## Options

  #{NimbleOptions.docs(@opts_schema)}

  ## When NOT to use this type

  If your column only ever holds a plain `interval`, you never feed it an ISO
  8601 string or a component map, and you would rather not take on the
  dependency, use Ecto's built-in `:duration` type directly instead. Otherwise,
  reach for this type and pick the `:format` that matches how you plan to query
  and store the value.

  ## Choosing a `:format`

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

  ## What a field accepts

  Casting takes a `Duration`, an ISO 8601 string, a component map with either
  string or atom keys, and `nil`, whatever the format. So `format: :native` accepts
  an ISO 8601 string where Ecto's built-in `:duration` would not.

  Reads are just as lenient: `load/3` accepts either stored shape regardless of the
  configured format, so a column holding a mix of both during a transition still
  reads cleanly.

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
  JSON encoder, `:native` cannot be used inside an embed or value object; using it
  there raises.

  ## Choosing an `:equality`

  `format: :native` must state one, because the two genuinely differ there and the
  wrong one is expensive: under `:strict`, a `Duration.new!(second: 10)` reads back
  from the column as `%Duration{second: 10, microsecond: {0, 6}}` and never compares
  equal to itself, so Ecto issues an update on every save. Under `:storage` both
  sides are first reduced to the three buckets an `interval` keeps, a month count, a
  day count, and a single microsecond count, so years fold into months, weeks into
  days, and everything below a day collapses into microseconds.

  For `:iso8601` and `:map` the option defaults to `:strict` and the two settings
  coincide, because both formats preserve the exact unit and the exact precision:
  `"PT10S"` and `"PT10.000000S"` are different strings, and `[0, 6]` is a different
  list from an omitted key.
  """

  use Ecto.ParameterizedType

  @postgres_default_precision 6

  @type format :: :iso8601 | :map | :native
  @type equality :: :storage | :strict

  @typedoc "A field's format and equality policy, built by Ecto from `field/3`."
  @type params :: %{format: format(), equality: equality()}

  @impl Ecto.ParameterizedType
  @spec init(keyword()) :: params()
  def init(opts) do
    opts = NimbleOptions.validate!(opts, @opts_schema)
    format = Keyword.fetch!(opts, :format)

    %{format: format, equality: equality!(opts, format)}
  end

  defp equality!(opts, :native) do
    case Keyword.fetch(opts, :equality) do
      {:ok, equality} ->
        equality

      :error ->
        raise ArgumentError,
              "missing :equality for Trogon.Ecto.DurationType with format: :native, " <>
                "expected one of :storage, :strict"
    end
  end

  defp equality!(opts, _format), do: Keyword.get(opts, :equality, :strict)

  @impl Ecto.ParameterizedType
  @spec type(params()) :: :string | :map | :duration
  def type(%{format: :iso8601}), do: :string
  def type(%{format: :map}), do: :map
  def type(%{format: :native}), do: :duration

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

  @impl Ecto.ParameterizedType
  @spec dump(term(), (Ecto.Type.t(), term() -> {:ok, term()} | :error), params()) ::
          {:ok, String.t() | map() | Duration.t() | nil} | :error
  def dump(nil, _dumper, _params), do: {:ok, nil}
  def dump(%Duration{} = value, _dumper, %{format: :iso8601}), do: {:ok, Duration.to_iso8601(value)}
  def dump(%Duration{} = value, _dumper, %{format: :map}), do: {:ok, to_component_map(value)}
  def dump(%Duration{} = value, _dumper, %{format: :native}), do: {:ok, value}
  def dump(_value, _dumper, _params), do: :error

  @impl Ecto.ParameterizedType
  @spec equal?(term(), term(), params()) :: boolean()
  def equal?(%Duration{} = value1, %Duration{} = value2, %{format: :native, equality: :storage}) do
    postgres_components(value1) == postgres_components(value2)
  end

  def equal?(value1, value2, _params), do: value1 == value2

  defp postgres_components(%Duration{} = duration) do
    {microsecond, _precision} = duration.microsecond
    second = 3600 * duration.hour + 60 * duration.minute + duration.second

    [
      month: 12 * duration.year + duration.month,
      day: 7 * duration.week + duration.day,
      microsecond: 1_000_000 * second + microsecond
    ]
  end

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
