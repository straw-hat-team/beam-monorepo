defmodule Trogon.TestWithoutMailboxVerificationTest do
  use ExUnit.Case, async: true
  use Trogon.Test, verify_mailbox: false

  test "does not verify the mailbox with verify_mailbox: false" do
    assert Process.get({Trogon.Test.Recorder, :tracker}) == nil
  end
end
