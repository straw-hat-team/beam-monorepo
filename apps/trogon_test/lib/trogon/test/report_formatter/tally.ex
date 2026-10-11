defmodule Trogon.Test.ReportFormatter.Tally do
  @moduledoc false

  defstruct total: 0, passed: 0, failed: 0, skipped: 0, excluded: 0, invalid: 0

  @reported_when_any [:failed, :skipped, :excluded, :invalid]

  @type t :: %__MODULE__{
          total: non_neg_integer(),
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          skipped: non_neg_integer(),
          excluded: non_neg_integer(),
          invalid: non_neg_integer()
        }

  @spec count(t(), ExUnit.Test.t()) :: t()
  def count(%__MODULE__{} = tally, %ExUnit.Test{state: state}) do
    key = outcome(state)
    %{tally | :total => tally.total + 1, key => Map.fetch!(tally, key) + 1}
  end

  @spec format(t(), non_neg_integer()) :: iodata()
  def format(%__MODULE__{} = tally, run_us) do
    status = if tally.failed == 0 and tally.invalid == 0, do: "ALL PASSED", else: "FAILURES"

    counts = [
      "#{tally.total} tests",
      "#{tally.passed} passed" | Enum.flat_map(@reported_when_any, &count_of(tally, &1))
    ]

    [status, " | ", Enum.join(counts, ", "), " | ", Integer.to_string(div(run_us, 1000)), "ms\n"]
  end

  defp count_of(tally, key) do
    case Map.fetch!(tally, key) do
      0 -> []
      count -> ["#{count} #{key}"]
    end
  end

  defp outcome(nil), do: :passed
  defp outcome({:failed, _failures}), do: :failed
  defp outcome({:skipped, _reason}), do: :skipped
  defp outcome({:excluded, _reason}), do: :excluded
  defp outcome({:invalid, _module}), do: :invalid
end
