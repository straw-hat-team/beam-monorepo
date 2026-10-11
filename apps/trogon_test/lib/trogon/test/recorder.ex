defmodule Trogon.Test.Recorder do
  @moduledoc false

  @enforce_keys [:owner]
  defstruct [:owner, :tracker]

  @type t :: %__MODULE__{owner: pid(), tracker: pid() | nil}
  @type message :: {Trogon.Test, {module(), {atom(), [term()]}}}

  @tracker {__MODULE__, :tracker}

  @spec new() :: t()
  def new, do: %__MODULE__{owner: self(), tracker: Process.get(@tracker)}

  @spec record(t(), message()) :: :ok
  def record(%__MODULE__{owner: owner, tracker: tracker}, message) do
    track(tracker, &[message | &1])
    send(owner, message)
    :ok
  end

  @spec asserted(message()) :: message()
  def asserted(message) do
    track(Process.get(@tracker), &List.delete(&1, message))
    message
  end

  @spec start_tracking() :: pid()
  def start_tracking do
    {:ok, tracker} = Agent.start(fn -> [] end)
    Process.put(@tracker, tracker)
    tracker
  end

  @spec verify!(pid()) :: :ok
  def verify!(tracker \\ Process.get(@tracker)) do
    case tracker |> Agent.get(& &1) |> Enum.reverse() do
      [] ->
        :ok

      unasserted ->
        raise ExUnit.AssertionError,
          message:
            "expected every call a Trogon.Test mock recorded to be asserted with an assert_received_* macro, " <>
              "but these were not:\n\n" <> Enum.map_join(unasserted, "\n", &"  #{inspect(&1)}")
    end
  end

  @spec stop_tracking(pid()) :: :ok
  def stop_tracking(tracker), do: Agent.stop(tracker)

  defp track(nil, _fun), do: :ok
  defp track(tracker, fun), do: Agent.update(tracker, fun)
end
