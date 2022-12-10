defmodule OnePiece.Nacha.AdvFileControl do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :batch_count,
    :block_count,
    :entry_and_addenda_count,
    :entry_hash,
    :total_debit_entry_dollar_amount_in_file,
    :total_credit_entry_dollar_amount_in_file,
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
         entry_and_addenda_count: Enum.at(parsed_line, 4),
         entry_hash: Enum.at(parsed_line, 3),
         total_debit_entry_dollar_amount_in_file: Enum.at(parsed_line, 2),
         total_credit_entry_dollar_amount_in_file: Enum.at(parsed_line, 1),
         reserved: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def file_control do
    string("9")
    |> label("Record Type Code")
    |> ascii_string([], 6)
    |> label("Batch Count")
    |> ascii_string([], 6)
    |> label("Block Count")
    |> ascii_string([], 8)
    |> label("Entry/Addenda Count")
    |> ascii_string([], 10)
    |> label("Entry Hash")
    |> ascii_string([], 20)
    |> label("Total Debit Entry Dollar Amount In File")
    |> ascii_string([], 20)
    |> label("Total Credit Entry Dollar Amount In File")
    |> ascii_string([], 23)
    |> label("Reserved")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:file_control)
    |> label("ADV File Control")
  end
end
