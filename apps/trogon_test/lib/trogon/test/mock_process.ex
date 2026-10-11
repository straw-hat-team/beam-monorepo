Mox.defmock(Trogon.Test.MockProcess,
  for: Trogon.Test.Behaviour.Process,
  moduledoc: """
  The Mox mock for `Trogon.Test.TestProcess`.

  Stub it with `Trogon.Test.TestProcess.stub/1`, then expect calls with
  `Trogon.Test.TestProcess.expect_send_after/1` and
  `Trogon.Test.TestProcess.expect_sleep/1`.
  """
)
