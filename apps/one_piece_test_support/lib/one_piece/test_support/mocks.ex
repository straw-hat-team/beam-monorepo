if Code.ensure_loaded?(Mox) do
  Mox.defmock(OnePiece.TestSupport.Mox.Task, for: OnePiece.TestSupport.Task)

  if Code.ensure_loaded?(OnePiece.Clock) do
    Mox.defmock(OnePiece.TestSupport.Mox.Clock, for: OnePiece.Clock)
  end

  if Code.ensure_loaded?(OnePiece.Commanded.Id) do
    Mox.defmock(OnePiece.TestSupport.Mox.Commanded.Id, for: OnePiece.Commanded.Id)
  end

  if Code.ensure_loaded?(Commanded.Application) do
    Mox.defmock(OnePiece.TestSupport.Mox.Commanded.Application, for: Commanded.Application)
  end
end
