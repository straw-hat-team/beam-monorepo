defmodule OnePiece.Nacha.ParsingInfo do
  @enforce_keys [:line, :byte_offset]
  defstruct @enforce_keys

  def new(line, byte_offset) do
    %__MODULE__{
      line: line,
      byte_offset: byte_offset
    }
  end
end
