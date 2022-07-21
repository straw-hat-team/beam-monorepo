defmodule OnePiece.Nacha do
  defmodule ParseError do
    defexception [:message]
  end

  def decode_file(input) do
    input
    |> OnePiece.Nacha.File.decode_file()
    |> normalize_output()
  end

  defp normalize_output({:ok, output, _rest, _, _, _}), do: {:ok, output[:file]}
  defp normalize_output(error), do: error
end
