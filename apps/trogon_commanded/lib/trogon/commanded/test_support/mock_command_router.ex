if Code.ensure_loaded?(Mox) and Code.ensure_loaded?(Trogon.Test.Recorder) do
  Mox.defmock(Trogon.Commanded.TestSupport.MockCommandRouter, for: Commanded.Application)
end
