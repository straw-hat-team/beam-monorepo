defmodule Trogon.Test.Recorder do
  @moduledoc """
  Records the calls a mock receives so `Trogon.Test.verify_mailbox_on_exit!/1`
  can report the ones a test never asserted.

  The `Trogon.Test.Test*` helpers are built on it, and a library can build
  mocks that take part in the same mailbox and verification.

  A mock follows these steps:

    1. Build a recorder with `new/0` in the test process, where the expectation
       is set up. The recorder remembers that process as the owner, and the
       tracking `verify_mailbox_on_exit!/1` started for it.
    2. Call `record/2` from inside the mock function. It may run in any
       process, since the recorder carries the owner and the tracking with it.
    3. Wrap the `assert_received` of the matching `assert_received_*` macro in
       `asserted/1`, so the call stops counting as unasserted.

  Every recorded call is sent to the owner as a message shaped
  `{Trogon.Test, {source_module, {function, args}}}`, where `source_module` is
  the module that defines the expectation and its assert macros. That tag is
  what `Trogon.Test.assert_empty_mailbox/0` looks for, so a third-party mock
  shows up there as well.

  ## Example

  A mailer mock built on Mox, with one expectation function and its assert
  macro:

      defmodule Acme.TestMailer do
        alias Trogon.Test.Recorder

        def expect_deliver(opts \\\\ []) do
          recorder = Recorder.new()
          returns = Keyword.get(opts, :returns, :ok)

          Mox.expect(Acme.MockMailer, :deliver, &record_deliver(recorder, &1, returns))
        end

        defp record_deliver(recorder, email, returns) do
          Recorder.record(recorder, {Trogon.Test, {__MODULE__, {:deliver, [email]}}})
          returns
        end

        defmacro assert_received_deliver(email) do
          quote do
            Recorder.asserted(
              ExUnit.Assertions.assert_received({Trogon.Test, {Acme.TestMailer, {:deliver, [unquote(email)]}}})
            )
          end
        end
      end

  A test then expects the call and asserts on it, and `verify_mailbox_on_exit!/1`
  fails the test if it forgets to:

      setup {Trogon.Test, :verify_mailbox_on_exit!}

      test "sends the welcome email" do
        Acme.TestMailer.expect_deliver()

        Acme.Accounts.register("ada@example.com")

        Acme.TestMailer.assert_received_deliver(%{to: "ada@example.com"})
      end
  """

  @enforce_keys [:owner]
  defstruct [:owner, :tracker]

  @type t :: %__MODULE__{owner: pid(), tracker: pid() | nil}
  @type message :: {Trogon.Test, {module(), {atom(), [term()]}}}

  @tracker {__MODULE__, :tracker}

  @doc """
  Builds a recorder owned by the calling process.

  Call it in the test process, where the expectation is set up, never inside
  the mock function, which may run in another process. The recorder keeps the
  test process as the owner that receives every recorded call, and the tracking
  `Trogon.Test.verify_mailbox_on_exit!/1` started, if it did.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{owner: self(), tracker: Process.get(@tracker)}

  @doc """
  Records a call, sending `message` to the owner and tracking it as unasserted.

  Call it from inside the mock function, from any process. The `message` is
  `{Trogon.Test, {source_module, {function, args}}}`.
  """
  @spec record(t(), message()) :: :ok
  def record(%__MODULE__{owner: owner, tracker: tracker}, message) do
    track(tracker, &[message | &1])
    send(owner, message)
    :ok
  end

  @doc """
  Marks `message` as asserted and returns it.

  Wrap the `assert_received` of an `assert_received_*` macro in it, in the test
  process, so `Trogon.Test.verify_mailbox_on_exit!/1` does not report the call.
  A call consumed any other way still counts as unasserted.
  """
  @spec asserted(message()) :: message()
  def asserted(message) do
    track(Process.get(@tracker), &List.delete(&1, message))
    message
  end

  @doc false
  @spec start_tracking() :: pid()
  def start_tracking do
    {:ok, tracker} = Agent.start(fn -> [] end)
    Process.put(@tracker, tracker)
    tracker
  end

  @doc false
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

  @doc false
  @spec stop_tracking(pid()) :: :ok
  def stop_tracking(tracker), do: Agent.stop(tracker)

  defp track(nil, _fun), do: :ok
  defp track(tracker, fun), do: Agent.update(tracker, fun)
end
