if Code.ensure_loaded?(Mox) and Code.ensure_loaded?(Trogon.Test.Recorder) do
  Mox.defmock(Trogon.Commanded.TestSupport.MockCommandedApplication, for: Commanded.Application)
end
