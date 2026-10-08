defmodule Trogon.Outbox.PostgresOutbox.PoolerGuardTest do
  use ExUnit.Case, async: true

  alias Trogon.Outbox.Relay.PoolerGuard

  describe "classify/2" do
    test "pooled when the sampled backend pid changes, regardless of how many probes held" do
      assert PoolerGuard.classify([1, 1, 2, 2, 2, 2], [:held, :held, :held, :held]) == :pooled
      assert PoolerGuard.classify([1, 2, 1, 2, 1, 2], [:held, :held, :held, :held]) == :pooled
      assert PoolerGuard.classify([1, 2], [:held, :failed, :failed, :failed]) == :pooled
    end

    test "direct when every sample is the same backend pid and at least one probe held" do
      assert PoolerGuard.classify([1, 1, 1, 1, 1, 1], [:held, :held, :held, :held]) == :direct
      assert PoolerGuard.classify([1, 1, 1, 1, 1, 1], [:held, :failed, :failed, :failed]) == :direct
      assert PoolerGuard.classify([1], [:held]) == :direct
    end

    test "inconclusive when every probe failed, even if the sampled pids differ" do
      assert PoolerGuard.classify([1, 1, 1, 1, 1, 1], [:failed, :failed, :failed, :failed]) == :inconclusive
      assert PoolerGuard.classify([1, 2, 1, 2, 1, 2], [:failed, :failed, :failed, :failed]) == :inconclusive
      assert PoolerGuard.classify([1], [:failed]) == :inconclusive
    end

    test "inconclusive takes precedence when there are no probe results at all" do
      assert PoolerGuard.classify([1, 2], []) == :inconclusive
    end
  end
end
