defmodule Trogon.TestVerifyMailboxOptionTest do
  use ExUnit.Case, async: true

  defmodule Default do
    use ExUnit.Case, async: true
    use Trogon.Test

    test "tracks recorded calls" do
      assert is_pid(Process.get({Trogon.Test.Recorder, :tracker}))
    end
  end

  defmodule Disabled do
    use ExUnit.Case, async: true
    use Trogon.Test, verify_mailbox: false

    test "does not track recorded calls" do
      assert Process.get({Trogon.Test.Recorder, :tracker}) == nil
    end
  end

  test "rejects an unknown option" do
    assert_raise ArgumentError, ~r/unknown keys \[:verify_mailbx\]/, fn ->
      Code.eval_quoted(
        quote do
          defmodule Trogon.TestVerifyMailboxOptionTest.Typo do
            use ExUnit.Case
            use Trogon.Test, verify_mailbx: true
          end
        end
      )
    end
  end
end
