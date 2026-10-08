defmodule Trogon.Outbox.TestSupport.ObanReply do
  @moduledoc false

  @doc """
  Job args are stored as JSON, so a test process pid travels through them as an
  encoded string and is decoded back inside the worker.
  """
  @spec encode(pid()) :: String.t()
  def encode(pid), do: pid |> :erlang.term_to_binary() |> Base.encode64()

  @spec send(Oban.Job.t(), term()) :: term()
  def send(%Oban.Job{args: %{"reply_to" => reply_to}}, message) do
    reply_to
    |> Base.decode64!()
    |> :erlang.binary_to_term()
    |> Kernel.send(message)
  end
end
