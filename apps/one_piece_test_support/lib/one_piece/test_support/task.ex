defmodule OnePiece.TestSupport.Task do
  @moduledoc """
  A Swiss Army Knife for `Task` around.
  """

  @callback async(func :: (() -> any())) :: Task.t()
end
