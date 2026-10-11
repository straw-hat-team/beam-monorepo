defmodule Trogon.Test.AIFormatter.Tally do
  @moduledoc false

  defstruct total: 0, passed: 0, failed: 0, skipped: 0, excluded: 0, invalid: 0, setup_all_failed: 0

  @reported_when_any [:failed, :skipped, :excluded, :invalid, :setup_all_failed]

  @type t :: %__MODULE__{
          total: non_neg_integer(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          skipped: non_neg_integer(),
          excluded: non_neg_integer(),
          invalid: non_neg_integer(),
          setup_all_failed: non_neg_integer()
        }

  @spec count(t(), ExUnit.Test.t()) :: t()
  def count(%__MODULE__{} = tally, %ExUnit.Test{state: state}) do
    key = outcome(state)
    %{tally | :total => tally.total + 1, key => Map.fetch!(tally, key) + 1}
  end

  @spec count_module(t(), ExUnit.TestModule.t()) :: t()
  def count_module(%__MODULE__{} = tally, %ExUnit.TestModule{state: {:failed, _failures}}) do
    %{tally | setup_all_failed: tally.setup_all_failed + 1}
  end

  def count_module(%__MODULE__{} = tally, %ExUnit.TestModule{}), do: tally

  @spec format(t(), non_neg_integer(), non_neg_integer() | nil) :: iodata()
  def format(%__MODULE__{} = tally, run_us, seed) do
    counts = [
      "#{tally.total} tests",
      "#{tally.passed} passed" | Enum.flat_map(@reported_when_any, &count_of(tally, &1))
    ]

    summary = [Enum.join(counts, ", "), " | ", Integer.to_string(div(run_us, 1000)), "ms"]

    if passed?(tally),
      do: ["ALL PASSED | ", summary, "\n"],
      else: ["FAILURES | ", summary, format_seed(seed), "\n"]
  end

  defp passed?(tally), do: tally.failed == 0 and tally.invalid == 0 and tally.setup_all_failed == 0

  # A failing run's order can be replayed with `mix test --seed`.
  defp format_seed(nil), do: []
  defp format_seed(seed), do: [" | seed ", Integer.to_string(seed)]

  defp count_of(tally, key) do
    case Map.fetch!(tally, key) do
      0 -> []
      count -> ["#{count} #{label(key)}"]
    end
  end

  defp label(:setup_all_failed), do: "setup_all failed"
  defp label(key), do: Atom.to_string(key)

  defp outcome(nil), do: :passed
  defp outcome({:failed, _failures}), do: :failed
  defp outcome({:skipped, _reason}), do: :skipped
  defp outcome({:excluded, _reason}), do: :excluded
  defp outcome({:invalid, _module}), do: :invalid
end
