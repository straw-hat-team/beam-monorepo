defmodule OnePiece.GracefulShutdownTest do
  use ExUnit.Case, async: false
  alias OnePiece.GracefulShutdown

  test "executing grateful shutdown" do
    delay = 70

    start_supervised!(
      {GracefulShutdown, [shutdown_delay_ms: delay, init_stop?: false, notify_pid: self()]}
    )

    assert [GracefulShutdown, _] = :gen_event.which_handlers(:erl_signal_server)
    assert :running = GracefulShutdown.get_status()

    {time, _} =
      :timer.tc(fn ->
        notify_sigterm()

        assert_receive :draining
        refute_received :stopping
        refute GracefulShutdown.running?(), "expected draining to have started"
        assert_receive :stopping
      end)

    assert time >= delay * 1000, "expected stop after delay time"
    assert time < (delay + 100) * 1000, "expected stopping message within 100ms of delay time"
  end

  defp notify_sigterm do
    :gen_event.notify(:erl_signal_server, :sigterm)
  end
end
