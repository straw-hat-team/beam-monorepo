defmodule Trogon.Telemetry.Instrument do
  @moduledoc """
  The metric a measurement feeds.

  A measurement is a number the event carries. An instrument says how that number should be aggregated over
  time, using the vocabulary of the OpenTelemetry metrics API. Declaring it next to the measurement keeps the
  aggregation, the unit and the documentation in one place, and lets `Trogon.Telemetry.Metrics` derive the
  `Telemetry.Metrics` definition instead of anyone writing it by hand.

  | Instrument         | Aggregates as             | `Telemetry.Metrics` |
  | ------------------ | ------------------------- | ------------------- |
  | `:counter`         | monotonic total           | `sum`               |
  | `:up_down_counter` | total that may go down    | `sum`               |
  | `:histogram`       | distribution of values    | `distribution`      |
  | `:gauge`           | latest value              | `last_value`        |

  ## Units

  `:unit` is the unit the recorded number is already in. Given a conversion pair such as
  `{:native, :millisecond}` or `{:byte, :kilobyte}`, `Telemetry.Metrics` converts on the way to the reporter,
  so nothing at the call site has to.

  ## Buckets

  `:buckets` is advisory, matching `ExplicitBucketBoundaries` in the OpenTelemetry metrics API: a hint from
  whoever declared the histogram about where the boundaries belong. Reporters disagree on how boundaries are
  configured, so this package records the hint and leaves the translation to the reporter. Use
  `:reporter_options` to reach a specific reporter, since it is passed through to `Telemetry.Metrics`
  untouched.
  """

  @typedoc """
  The kind of aggregation a measurement feeds.
  """
  @type kind :: :counter | :up_down_counter | :histogram | :gauge

  @typedoc """
  A unit, or a pair converting the recorded unit into the reported one.
  """
  @type unit :: atom() | {atom(), atom()}

  @type t :: %__MODULE__{
          kind: kind(),
          unit: unit(),
          buckets: [number(), ...] | nil,
          tags: [atom()] | nil,
          reporter_options: keyword()
        }

  @enforce_keys [:kind]
  defstruct [
    :kind,
    :buckets,
    :tags,
    unit: :unit,
    reporter_options: []
  ]

  @kinds [:counter, :up_down_counter, :histogram, :gauge]

  @doc """
  Every instrument kind.
  """
  @spec kinds() :: [kind(), ...]
  def kinds, do: @kinds

  @doc """
  Whether a term names an instrument kind.
  """
  @spec kind?(term()) :: boolean()
  def kind?(kind), do: kind in @kinds

  @doc """
  The `Telemetry.Metrics` definition an instrument maps to.

  The mapping is the whole point of declaring a kind: a counter can only ever become a sum, so a metric
  cannot silently disagree with the measurement feeding it.
  """
  @spec aggregation(t()) :: :sum | :last_value | :distribution
  def aggregation(%__MODULE__{kind: kind}) when kind in [:counter, :up_down_counter], do: :sum
  def aggregation(%__MODULE__{kind: :gauge}), do: :last_value
  def aggregation(%__MODULE__{kind: :histogram}), do: :distribution

  @doc """
  A human readable name for a unit, used by the generated documentation.
  """
  @spec unit_to_string(unit()) :: String.t()
  def unit_to_string({from, to}), do: "#{from} as #{to}"
  def unit_to_string(:unit), do: ""
  def unit_to_string(unit), do: Atom.to_string(unit)
end
