defmodule OnePiece.Nacha.BatchControl do
  import NimbleParsec
  import OnePiece.Nacha.Helpers

  @enforce_keys [
    :record_type_code,
    :service_class_code,
    :entry_addenda_count,
    :entry_hash,
    :total_debit_entries,
    :total_credit_entries,
    :company_identification,
    :message_authentication_code,
    :reserved,
    :originating_dfi_identification,
    :batch_number,
    :__parsing_info__
  ]

  defstruct @enforce_keys

  def post_traverse(rest, parsed_line, context, line, byte_offset) do
    {rest,
     [
       %__MODULE__{
         record_type_code: Enum.at(parsed_line, 10),
         service_class_code: Enum.at(parsed_line, 9),
         entry_addenda_count: Enum.at(parsed_line, 8),
         entry_hash: Enum.at(parsed_line, 7),
         total_debit_entries: Enum.at(parsed_line, 6),
         total_credit_entries: Enum.at(parsed_line, 5),
         company_identification: Enum.at(parsed_line, 4),
         message_authentication_code: Enum.at(parsed_line, 3),
         reserved: Enum.at(parsed_line, 2),
         originating_dfi_identification: Enum.at(parsed_line, 1),
         batch_number: Enum.at(parsed_line, 0),
         __parsing_info__: OnePiece.Nacha.ParsingInfo.new(line, byte_offset)
       }
     ], context}
  end

  def batch_control do
    string("8")
    |> label("Record Type Code")
    |> integer(3)
    |> label("Service Class Code")
    |> integer(6)
    |> label("Entry / Addenda Count")
    |> integer(10)
    |> label("Entry Hash")
    |> integer(12)
    |> label("Total Debit Entry Dollar Amount")
    |> integer(12)
    |> label("Total Credit Entry Dollar Amount")
    |> trimmed_ascii_string([], 10)
    |> label("Company Identification")
    |> ascii_string([], 19)
    |> label("Message Authentication Code")
    |> ascii_string([], 6)
    |> label("Reserved")
    |> ascii_string([], 8)
    |> label("Originating DFI Identification")
    |> integer(7)
    |> label("Batch Number")
    |> eol()
    |> post_traverse({__MODULE__, :post_traverse, []})
    |> unwrap_and_tag(:batch_control)
    |> label("Batch Control")
  end
end
