defmodule Trogon.Outbox.ObanPro.Counter do
  @moduledoc false

  @table :trogon_outbox_oban_pro_counters

  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:public, :named_table, :set, write_concurrency: true])
    end

    :ok
  end

  @spec bump(term(), integer()) :: integer()
  def bump(key, delta \\ 1) do
    :ets.update_counter(@table, key, {2, delta}, {key, 0})
  end

  @spec get(term()) :: integer()
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, val}] -> val
      [] -> 0
    end
  end

  @doc "Keeps a running high-water mark: only ever moves up."
  @spec max_update(term(), integer()) :: :ok | true
  def max_update(key, value) do
    case :ets.lookup(@table, key) do
      [{^key, current}] when current >= value -> :ok
      _ -> :ets.insert(@table, {key, value})
    end
  end
end
