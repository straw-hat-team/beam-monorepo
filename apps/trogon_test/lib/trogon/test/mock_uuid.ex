if Code.ensure_loaded?(Uniq.UUID) do
  Mox.defmock(Trogon.Test.MockUUID,
    for: Trogon.Test.Behaviour.UUID,
    moduledoc: """
    The Mox mock for `Trogon.Test.TestUUID`.

    Stub it with `Trogon.Test.TestUUID.stub/1`, then expect calls with
    `Trogon.Test.TestUUID.expect_uuid4/1` and `Trogon.Test.TestUUID.expect_uuid7/1`.
    """
  )
end
