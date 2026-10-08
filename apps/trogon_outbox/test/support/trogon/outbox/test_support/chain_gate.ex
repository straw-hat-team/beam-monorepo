defmodule Trogon.Outbox.TestSupport.ChainGate do
  @moduledoc false

  alias Ecto.Adapters.SQL

  @blocking_states ~w(executing pending)
  @terminal_states ~w(discarded cancelled)

  @type policy :: :ignore | :hold | :halt
  @type decision :: :publish | :wait | :hold | :halt

  @doc """
  Reference implementation of the predecessor check a chained job worker runs
  before publishing: look up the latest earlier job for the same source that
  has not completed yet, and decide what to do about the job at `id`.
  """
  @spec decide(Ecto.Repo.t(), String.t(), pos_integer(), policy()) :: decision()
  def decide(repo, source, id, policy) do
    case predecessor(repo, source, id) do
      nil ->
        :publish

      {_predecessor_id, state} when state in @blocking_states ->
        :wait

      {_predecessor_id, state} when state in @terminal_states ->
        resolve(policy)
    end
  end

  defp predecessor(repo, source, id) do
    %Postgrex.Result{rows: rows} =
      SQL.query!(
        repo,
        "SELECT id, state FROM outbox_jobs WHERE source = $1 AND id < $2 AND state != 'completed' ORDER BY id DESC LIMIT 1",
        [source, id]
      )

    case rows do
      [[predecessor_id, state]] -> {predecessor_id, state}
      [] -> nil
    end
  end

  defp resolve(:ignore), do: :publish
  defp resolve(:hold), do: :hold
  defp resolve(:halt), do: :halt
end
