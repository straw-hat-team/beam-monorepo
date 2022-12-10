defmodule OnePiece.Nacha.AdvBatchControl do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :service_class_code,
    :entry_and_addenda_count,
    :entry_hash,
    :total_debit_entry_dollar_amount,
    :total_credit_entry_dollar_amount,
    :ach_operator_data,
    :originating_dfi_identification,
    :batch_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 8),
         service_class_code: Enum.at(parsed_line, 7),
         entry_and_addenda_count: Enum.at(parsed_line, 6),
         entry_hash: Enum.at(parsed_line, 5),
         total_debit_entry_dollar_amount: Enum.at(parsed_line, 4),
         total_credit_entry_dollar_amount: Enum.at(parsed_line, 3),
         ach_operator_data: Enum.at(parsed_line, 2),
         originating_dfi_identification: Enum.at(parsed_line, 1),
         batch_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def batch_control do
    string("8")
    |> label("Record Type Code")
    |> ascii_string([], 3)
    |> label("Service Class Code")
    |> ascii_string([], 6)
    |> label("Entry/Addenda Count")
    |> ascii_string([], 10)
    |> label("Entry Hash")
    |> ascii_string([], 20)
    |> label("Total Debit Entry Dollar Amount")
    |> ascii_string([], 20)
    |> label("Total Credit Entry Dollar Amount")
    |> ascii_string([], 19)
    |> label("Ach Operator Data")
    |> ascii_string([], 8)
    |> label("Originating DFI Identification")
    |> ascii_string([], 7)
    |> label("Batch Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:batch_control)
    |> label("ADV Batch Control")
  end
end
