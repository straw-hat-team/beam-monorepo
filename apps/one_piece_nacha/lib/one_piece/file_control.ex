defmodule OnePiece.Nacha.FileControl do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :batch_count,
    :block_count,
    # TODO: name is confusing
    :entry_addenda_count,
    :entry_hash,
    :total_debits,
    :total_credits,
    # TODO: probably remove this
    :reserved,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 7),
         batch_count: Enum.at(parsed_line, 6),
         block_count: Enum.at(parsed_line, 5),
         entry_addenda_count: Enum.at(parsed_line, 4),
         entry_hash: Enum.at(parsed_line, 3),
         total_debits: Enum.at(parsed_line, 2),
         total_credits: Enum.at(parsed_line, 1),
         reserved: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def file_control do
    string("9")
    |> label("Record Type Code")
    |> integer(6)
    |> label("Batch Count")
    |> integer(6)
    |> label("Block Count")
    |> integer(8)
    |> label("Entry / Addenda Count")
    |> integer(10)
    |> label("Entry Hash")
    |> integer(12)
    |> label("Total Debit Entry Dollar Amount in File")
    |> integer(12)
    |> label("Total Credit Entry Dollar Amount in File")
    |> ascii_string([], 39)
    |> label("Reserved")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:file_control)
    |> label("File Control")
  end
end
