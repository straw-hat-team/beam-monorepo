defmodule Trogon.Test.AcmeMailer do
  alias Trogon.Test.Recorder

  def expect_deliver(email) do
    recorder = Recorder.new()

    fn -> deliver(recorder, email) end
  end

  defp deliver(recorder, email) do
    Recorder.record(recorder, {Trogon.Test, {__MODULE__, {:deliver, [email]}}})
  end

  defmacro assert_received_deliver(email) do
    quote do
      Recorder.asserted(
        ExUnit.Assertions.assert_received({Trogon.Test, {unquote(__MODULE__), {:deliver, [unquote(email)]}}})
      )
    end
  end
end
